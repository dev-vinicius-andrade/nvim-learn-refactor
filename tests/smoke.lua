-- run: nvim --headless -u NONE -l tests/smoke.lua   (from repo root)
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/learn-refactor.lua")

local failures = 0
local function check(name, cond, extra)
  if cond then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or ""))
  end
end

local tmp = vim.fn.tempname()
require("learn_refactor").setup({ provider = "static", data_dir = tmp, keymaps = {}, control_bar = true })
local scoring = require("learn_refactor.scoring")
local seeds = require("learn_refactor.seeds")

-- every seed check must fail on original code (no free points) and be a valid regex
for _, seed in ipairs(seeds) do
  for _, b in ipairs(seed.bugs) do
    check(seed.title .. "/" .. b.id .. " fails on original", scoring.run_check(b.fixed, seed.code) == false)
  end
  for _, s in ipairs(seed.standards) do
    check(seed.title .. "/" .. s.id .. " fails on original", scoring.run_check(s.check, seed.code) == false)
  end
end

-- parse
local gen = require("learn_refactor.generator")
local ch = gen.parse('```json\n{"title":"t","code":"x=1","bugs":[],"standards":[]}\n```')
check("parse fenced json", ch and ch.title == "t")
check("parse garbage rejected", gen.parse("nope") == nil)
check("prompt builds", #gen.build_prompt("lua", "easy") > 200)

-- fallback -> store
local lua_ch = gen.fallback("lua", "easy")
check("fallback returns lua seed", lua_ch and lua_ch.language == "lua" and lua_ch.id)
check("challenge saved", #require("learn_refactor.store").list_challenges() == 1)

-- session lifecycle
local session = require("learn_refactor.session")
session.open(lua_ch)
check("session ready", session.current and session.current.state == "ready")
check("buffer locked when ready", vim.bo[session.current.buf].modifiable == false)
session.play()
check("running + modifiable", session.current.state == "running" and vim.bo[session.current.buf].modifiable)
session.pause()
check("paused locks buffer", session.current.state == "paused" and not vim.bo[session.current.buf].modifiable)
session.play()
check("statusline", session.statusline():find("keys:") ~= nil, session.statusline())

local fixed = [[
local TAX_THRESHOLD = 100
local DISCOUNT = 10

local function order_total(items)
  local total = 0
  for i = 1, #items do
    total = total + items[i].price * items[i].qty
  end
  if total > TAX_THRESHOLD then
    total = total - total * DISCOUNT / 100
  end
  return total
end
]]
vim.api.nvim_buf_set_lines(session.current.buf, 0, -1, false, vim.split(fixed, "\n", { plain = true }))

local result
local orig = scoring.score
scoring.score = function(c, t, m, cb)
  return orig(c, t, m, function(r)
    result = r
    cb(r)
  end)
end
session.finish()
vim.wait(2000, function() return result ~= nil end)
check("score produced", result ~= nil)
if result then
  for _, l in ipairs(result.lines) do print(string.format("     %s %s %d", l.ok and "+" or "-", l.label, l.points)) end
  print("     total", result.points, "/", result.max_points)
  check("bug credited", result.lines[1].ok)
  check("session cleared", session.current == nil)
  check("history written", #require("learn_refactor.store").history() == 1)
  check("profile updated", require("learn_refactor.store").profile().total_points > 0)
end

-- stop path
session.open(lua_ch)
check("control bar open with 6 spans (incl. menu)", session.current.bar_win and #session.current.bar_spans == 6)
session.play()
vim.api.nvim_set_current_win(session.current.win)
vim.api.nvim_feedkeys("jjjjjjjj", "xt", false)
vim.api.nvim_feedkeys(vim.keycode("<Down><Down>"), "xt", false)
check("jjjjjjjj counted as hjkl spam", session.current.metrics.spam >= 3, vim.inspect(session.current.metrics))
check("arrows counted", session.current.metrics.arrows == 2, vim.inspect(session.current.metrics))
session.hint()
check("hint counted", session.current.metrics.hints == 1)
session.stop(true)
check("stop clears session", session.current == nil)

-- generate path with a mock provider (invalid + valid checks)
package.loaded["learn_refactor.provider.mock"] = {
  request = function(_, cb)
    cb(vim.json.encode({
      title = "Mock",
      description = "d",
      code = "local x = 1\nreturn x\n",
      bugs = {
        { id = "free", fixed = { type = "absent", pattern = "nomatch" } }, -- true on original -> dropped
        { id = "bad", fixed = { type = "absent", pattern = "(" } }, -- invalid regex -> dropped
        { id = "ok", points = 20, fixed = { type = "absent", pattern = "local x" } },
      },
      standards = {},
    }))
  end,
}
require("learn_refactor.config").options.provider = "mock"
local generated
gen.generate("lua", "medium", function(c, err) generated = c or { err = err } end)
vim.wait(1000, function() return generated ~= nil end)
check("generate ok", generated and generated.id, generated and generated.err)
check("invalid/free checks dropped", generated and #generated.bugs == 1 and generated.bugs[1].id == "ok")
check("generated saved to library", #require("learn_refactor.store").list_challenges({ complexity = "medium" }) == 1)

-- failing provider -> fallback
package.loaded["learn_refactor.provider.mock"] = { request = function(_, cb) cb(nil, "boom") end }
local fb
gen.generate("python", "easy", function(c, err) fb = c or { err = err } end)
vim.wait(1000, function() return fb ~= nil end)
check("provider failure falls back to seed", fb and fb.language == "python", fb and fb.err)

-- openai-compatible provider + routing, with vim.system mocked
local real_system = vim.system
local captured
vim.system = function(args, o, on_exit)
  captured = { args = args, stdin = o.stdin }
  local reply = vim.json.encode({ choices = { { message = { content = vim.json.encode({
    title = "Routed", description = "d", code = "local y = 2\nreturn y\n",
    bugs = { { id = "b", points = 10, fixed = { type = "absent", pattern = "local y" } } }, standards = {},
  }) } } } })
  vim.schedule(function() on_exit({ code = 0, stdout = reply, stderr = "" }) end)
end
local cfg = require("learn_refactor.config").options
cfg.provider = "static"
cfg.openai.model = "local-model"
cfg.openai.base_url = "http://localhost:11434/v1/"
cfg.routes = { easy = { provider = "openai", model = "routed-model" } }
local routed
gen.generate("lua", "easy", function(c, err) routed = c or { err = err } end)
vim.wait(1000, function() return routed ~= nil end)
check("openai route generates", routed and routed.title == "Routed", routed and routed.err)
check("route model sent", captured and captured.stdin:find('"routed%-model"') ~= nil)
check("base_url slash trimmed", captured and vim.tbl_contains(captured.args, "http://localhost:11434/v1/chat/completions"), captured and vim.inspect(captured.args))
check("no auth header without api_key_env", captured and not vim.tbl_contains(captured.args, "authorization"))

cfg.routes = { easy = { provider = "nope" } }
local unknown
gen.generate("lua", "easy", function(c, err) unknown = c or { err = err } end)
vim.wait(1000, function() return unknown ~= nil end)
check("unknown provider falls back", unknown and unknown.language == "lua", unknown and unknown.err)
vim.system = real_system

-- coach
local coach = require("learn_refactor.coach")
local log = {}
for _ = 1, 8 do log[#log + 1] = { "j", "n" } end
for _ = 1, 7 do log[#log + 1] = { "<BS>", "i" } end
local tips, stats = coach.analyze(log, { arrows = 2, mouse = 1 })
local joined = table.concat(tips, "\n")
check("coach: j run", joined:find("8 j/k") ~= nil, joined)
check("coach: backspace run", joined:find("7 backspaces") ~= nil, joined)
check("coach: arrows+mouse", joined:find("2 arrow") ~= nil and joined:find("1 mouse") ~= nil, joined)
check("coach: stats", stats.vertical == 8)
local clean = {}
for _, k in ipairs({ "d", "i", "w" }) do clean[#clean + 1] = { k, k == "i" and "no" or "n" } end
check("coach: clean log", coach.analyze(clean, {})[1]:find("No bad habits") ~= nil)

-- advisor
local advisor = require("learn_refactor.advisor")
vim.o.relativenumber = false
local atips = advisor.analyze({ stats = { vertical = 10 }, metrics = {}, lsp = false })
check("advisor: has tips", #atips > 3)
check("advisor: relevant tips first", atips[1].relevant == true)
local text = table.concat(advisor.lines({}, 50), "\n")
check("advisor: relativenumber tip", text:find("relativenumber") ~= nil)
vim.o.relativenumber = true
check("advisor: tip disappears when fixed", table.concat(advisor.lines({}, 50), "\n"):find("relativenumber") == nil)

-- hidden tests + anti-gaming
cfg.languages.lua.test = "nvim --headless -u NONE -l {test}" -- use the running nvim as the lua runner
cfg.run_tests = true
local test_ch = {
  id = "t1", language = "lua", complexity = "easy",
  code = "local M = {}\nfunction M.add(a, b)\n  return a - b\nend\nreturn M\n",
  solution = "local M = {}\nfunction M.add(a, b)\n  return a + b\nend\nreturn M\n",
  bugs = { { id = "sub", points = 30, fixed = { type = "absent", pattern = "a - b" } } },
  standards = { { id = "named", tag = "naming", points = 10, check = { type = "present", pattern = "function M\\.add" } } },
  tests = { code = "package.path = './?.lua;' .. package.path\nlocal m = require('main')\nassert(m.add(2, 3) == 5, 'add broken')\nvim.cmd('qa!')\n" },
}
local function run_score(text_in, ch_in)
  local res
  scoring.score(ch_in or test_ch, text_in, { seconds = 9999, keys = 1, arrows = 0, mouse = 0, spam = 0, hints = 0 }, function(r) res = r end)
  vim.wait(20000, function() return res ~= nil end)
  return res
end
local passing = run_score(test_ch.solution)
check("tests pass on solution", passing and passing.tests_ok == true, passing and passing.test_output)
local broken = run_score("local M = {}\nfunction M.add(a, b)\n  return a * b\nend\nreturn M\n")
check("tests fail on wrong behaviour", broken and broken.tests_ok == false)
local bug_line
for _, l in ipairs(broken and broken.lines or {}) do if l.label:find("^Bug") then bug_line = l end end
check("credit halved when tests fail", bug_line and bug_line.points == 15, bug_line and bug_line.points)
local gutted = run_score("return {}\n", vim.tbl_extend("force", test_ch, { code = string.rep("local x = 1\n", 10) }))
check("deleting everything scores 0", gutted and gutted.points == 0 and gutted.note ~= nil)
local same = run_score(test_ch.code)
check("unchanged scores 0", same and same.points == 0)

-- generator validates tests against solution; bad tests dropped
package.loaded["learn_refactor.provider.mock"] = {
  request = function(_, cb)
    cb(vim.json.encode(vim.tbl_extend("force", test_ch, { id = vim.NIL, title = "T", description = "d",
      tests = { code = "error('always fails')" } })))
  end,
}
cfg.routes = {}
cfg.provider = "mock"
local gen_bad
gen.generate("lua", "easy", function(c, err) gen_bad = c or { err = err } end)
vim.wait(20000, function() return gen_bad ~= nil end)
check("tests failing on solution are dropped", gen_bad and gen_bad.tests == nil and gen_bad.solution ~= nil, gen_bad and gen_bad.err)
package.loaded["learn_refactor.provider.mock"] = {
  request = function(_, cb)
    cb(vim.json.encode(vim.tbl_extend("force", test_ch, { id = vim.NIL, title = "T2", description = "d", run_cmd = "rm -rf /" })))
  end,
}
local gen_good
gen.generate("lua", "easy", function(c, err) gen_good = c or { err = err } end)
vim.wait(20000, function() return gen_good ~= nil end)
check("valid tests kept", gen_good and gen_good.tests ~= nil, gen_good and gen_good.err)
check("model-supplied run_cmd stripped", gen_good and gen_good.run_cmd == nil)

-- ollama container management (vim.system mocked)
local ollama = require("learn_refactor.ollama")
local ocfg = cfg.ollama
ocfg.runtime = "podman"
local args_cpu = ollama.compose_args("podman", false)
local args_gpu = ollama.compose_args("podman", true)
local args_docker_gpu = ollama.compose_args("docker", true)
check("compose cpu: base + bridge", #args_cpu == 6 and args_cpu[4]:find("compose.yaml$") ~= nil and args_cpu[6]:find("compose.bridge.yaml$") ~= nil, vim.inspect(args_cpu))
check("compose host network file", ollama.compose_args("podman", false, "host")[6]:find("compose.host.yaml$") ~= nil)
check("compose podman gpu: CDI override", args_gpu[#args_gpu]:find("compose.gpu.yaml$") ~= nil)
check("compose docker gpu: deploy override", args_docker_gpu[#args_docker_gpu]:find("compose.gpu%-docker.yaml$") ~= nil)
ollama.has_cdi = function() return false end
ocfg.gpu = true
check("gpu=true without CDI is flagged", ollama.use_gpu("podman") == "missing-cdi")
check("docker gpu needs no CDI", ollama.use_gpu("docker") == true)
ocfg.gpu = false
check("gpu=false", ollama.use_gpu("podman") == false)

local calls = {}
vim.system = function(args, o, on_exit)
  calls[#calls + 1] = table.concat(args, " ")
  local res = { code = 0, stdout = "", stderr = "" }
  if args[1] == "curl" then
    res.stdout = vim.json.encode({ models = {} }) -- up, but model missing
  end
  vim.schedule(function() on_exit(res) end)
end
ocfg.model = "qwen2.5-coder:14b"
local up_ok, up_err
ollama.up(function(ok, err) up_ok, up_err = ok, err end)
vim.wait(2000, function() return up_ok ~= nil end)
check("ollama up succeeds", up_ok == true, up_err)
check("up runs compose up -d", calls[1] and calls[1]:find("podman compose %-f .-compose.yaml %-f .-compose.bridge.yaml up %-d") ~= nil, calls[1])
check("up pulls missing model", calls[#calls] and calls[#calls]:find("exec learn%-refactor%-ollama ollama pull qwen2.5%-coder:14b") ~= nil, calls[#calls])
check("is_local", ollama.is_local("http://localhost:11434/v1") and not ollama.is_local("https://api.groq.com/openai/v1"))

-- auto_start hooks the openai provider
calls = {}
ocfg.auto_start = true
ocfg.model = "m1"
cfg.openai.model = "m1"
cfg.openai.base_url = "http://localhost:11434/v1"
local ensured = false
ollama.ensure = function(cb) ensured = true cb(false, "no container runtime") end
local auto_err
require("learn_refactor.provider.openai").request("p", function(t, e) auto_err = e end, {})
check("openai provider calls ensure() and surfaces failure", ensured and auto_err == "no container runtime", auto_err)
ocfg.auto_start = false
vim.system = real_system

-- literal checks, stray , retry on weak output
check("literal absent", scoring.run_check({ type = "absent", literal = "for i = 0," }, "for i = 1, n") == true)
check("literal present", scoring.run_check({ type = "present", literal = "range(len(" }, "x in range(len(a))") == true)
check("literal is not a regex", scoring.run_check({ type = "present", literal = "a.c" }, "abc") == false)
check("stray \\v tolerated", scoring.run_check({ type = "present", pattern = "\\vfoo+" }, "foooo") == true)
check("check without literal/pattern is invalid", scoring.run_check({ type = "present" }, "x") == nil)

cfg.provider, cfg.routes, cfg.min_checks, cfg.attempts = "mock", {}, 3, 3
local calls_n = 0
local function reply(bugs, stds)
  return vim.json.encode({ title = "Retry" .. calls_n, description = "d", code = "x = 1\ny = 2\n", bugs = bugs, standards = stds })
end
package.loaded["learn_refactor.provider.mock"] = {
  request = function(_, cb)
    calls_n = calls_n + 1
    if calls_n == 1 then -- weak: only one usable check
      return cb(reply({ { id = "a", fixed = { type = "absent", literal = "x = 1" } } }, {}))
    end
    cb(reply({ { id = "a", fixed = { type = "absent", literal = "x = 1" } } },
      { { id = "s1", tag = "t", check = { type = "present", literal = "total" } },
        { id = "s2", tag = "t", check = { type = "present", literal = "count" } } }))
  end,
}
local retried
gen.generate("lua", "easy", function(c, err) retried = c or { err = err } end)
vim.wait(5000, function() return retried ~= nil end)
check("weak first attempt triggers retry", calls_n == 2, calls_n)
check("retry result accepted (3 checks)", retried and #retried.bugs + #retried.standards == 3, retried and retried.err)

calls_n = 0
package.loaded["learn_refactor.provider.mock"] = {
  request = function(_, cb)
    calls_n = calls_n + 1
    cb(reply({ { id = "a", fixed = { type = "absent", literal = "x = 1" } } }, {}))
  end,
}
local best
gen.generate("lua", "easy", function(c, err) best = c or { err = err } end)
vim.wait(5000, function() return best ~= nil end)
check("attempts capped, best kept", calls_n == 3 and best and #best.bugs == 1, calls_n)

-- regression: keymaps = false (lazy.nvim `keys` owns the mappings) must not break sessions
local saved_keymaps = cfg.keymaps
cfg.keymaps = false
local ok_open, open_err = pcall(function()
  session.open(lua_ch)
  session.stop(true)
end)
check("session opens with keymaps = false", ok_open, open_err)
if not ok_open and session.current then session.stop(true) end
cfg.keymaps = saved_keymaps
require("learn_refactor").setup({ provider = "static", data_dir = tmp, keymaps = false })
check("setup accepts keymaps = false", true)

-- floating menu
local menu = require("learn_refactor.menu")
local function keys_of(items) local k = {} for _, it in ipairs(items) do k[#k + 1] = it.key end return table.concat(k) end
check("menu idle items", keys_of(menu.items()) == "nlgtudi", keys_of(menu.items()))
session.open(lua_ch)
check("menu ready items", keys_of(menu.items()) == "ps", keys_of(menu.items()))
menu.open()
check("menu float opened", vim.api.nvim_win_get_config(0).relative == "editor")
vim.api.nvim_feedkeys("q", "xt", false)
check("q closes menu", vim.api.nvim_win_get_config(0).relative == "")
menu.open()
vim.api.nvim_feedkeys("p", "xt", false)
vim.wait(500, function() return session.current.state == "running" end)
check("hotkey p plays", session.current.state == "running")
check("menu running items", keys_of(menu.items()) == "zfhs", keys_of(menu.items()))
menu.open()
vim.api.nvim_feedkeys("z", "xt", false)
vim.wait(500, function() return session.current.state == "paused" end)
check("hotkey z pauses", session.current.state == "paused")
check("menu paused items", keys_of(menu.items()) == "pfs", keys_of(menu.items()))
menu.open()
vim.api.nvim_feedkeys("s", "xt", false)
vim.wait(500, function() return session.current == nil end)
check("hotkey s stops", session.current == nil)

-- menu shows real key bindings + help
vim.g.mapleader = " "
local function menu_text()
  local lines = menu.render(menu.items())
  return table.concat(lines, "\n")
end
-- the earlier setup() calls mapped the default keys (deep-merge keeps defaults); start from a clean slate
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if (m.desc or ""):match("^LearnRefactor ") then pcall(vim.keymap.del, "n", m.lhs) end
end
local before = menu_text()
check("menu: idle shows commands", before:find(":RefactorLibrary", 1, true) ~= nil)
check("menu: help block", before:find("How to use this menu", 1, true) ~= nil)
check("menu: no-keys hint when nothing mapped", before:find("no keys are mapped yet", 1, true) ~= nil, before)
vim.keymap.set("n", "<leader>Rr", "<cmd>Refactor<cr>")           -- lazy `keys` style
vim.keymap.set("n", "<leader>Rl", ":RefactorLibrary<CR>")
vim.keymap.set("n", "<leader>Rm", "<cmd>RefactorMenu<cr>")
vim.keymap.set("n", "<leader>Rt", function() end, { desc = "LearnRefactor config_tips" }) -- setup() style
local after = menu_text()
check("menu: lazy-style key shown", after:find("<leader>Rr", 1, true) ~= nil, after)
check("menu: colon-style key shown", after:find("<leader>Rl", 1, true) ~= nil)
check("menu: setup()-style key shown", after:find("<leader>Rt", 1, true) ~= nil)
check("menu: reopen hint uses menu key", after:find("reopen this menu: <leader>Rm or :RefactorMenu", 1, true) ~= nil, after)
check("menu: no 'no keys' hint once mapped", after:find("no keys are mapped yet", 1, true) == nil)
check("menu: unmapped action shows dash", after:find("-  :RefactorStats", 1, true) ~= nil or after:find("%-%s+:RefactorStats") ~= nil, after)
menu.open()
vim.api.nvim_feedkeys("G", "xt", false) -- cursor must stay on an item row, never on help text
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() }) -- headless: no redraw loop to fire it
local row = vim.api.nvim_win_get_cursor(0)[1]
check("menu: cursor clamped to items", row == 1 + #menu.items(), row)
vim.api.nvim_feedkeys("q", "xt", false)

-- menu key shown where new users look: bar, info window
session.open(lua_ch)
local bar_line = vim.api.nvim_buf_get_lines(session.current.bar_buf, 0, 1, false)[1]
check("bar shows menu key", bar_line:find("Menu <leader>Rm", 1, true) ~= nil, bar_line)
check("bar has a clickable menu span", session.current.bar_spans[6] and session.current.bar_spans[6].action == "menu")
local info = table.concat(vim.api.nvim_buf_get_lines(session.current.info_buf, 0, -1, false), " ")
check("info window shows menu key", info:find("Actions menu", 1, true) ~= nil and info:find("<leader>Rm", 1, true) ~= nil, info)
session.stop(true)
vim.keymap.del("n", "<leader>Rm")
session.open(lua_ch)
local bar_line2 = vim.api.nvim_buf_get_lines(session.current.bar_buf, 0, 1, false)[1]
check("bar falls back to :RefactorMenu when unmapped", bar_line2:find(":RefactorMenu", 1, true) ~= nil, bar_line2)
session.stop(true)
vim.keymap.set("n", "<leader>Rm", "<cmd>RefactorMenu<cr>")

-- teaching tips tied to habits
local tips = require("learn_refactor.tips")
local general = tips.pick({})
check("tips: general tip", type(general) == "string" and #general > 10)
local habit_tip, habit = tips.pick({ vertical = 30, mouse = 2 })
check("tips: picks the biggest habit", habit == "vertical" and habit_tip ~= nil)
require("learn_refactor.store").add_habits({ vertical = 8, horizontal = 0, arrows = 2 })
require("learn_refactor.store").add_habits({ vertical = 4 })
local habits = require("learn_refactor.store").profile().habits
check("habits accumulate in profile", habits.vertical == 12 and habits.arrows == 2 and habits.horizontal == nil, vim.inspect(habits))
check("menu shows habit tip", menu_text():find("Tip for your habits:", 1, true) ~= nil)

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
vim.cmd(failures == 0 and "qa!" or "cq!")

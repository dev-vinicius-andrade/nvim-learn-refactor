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
check("control bar open with 5 spans", session.current.bar_win and #session.current.bar_spans == 5)
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
check("compose cpu: one file", #args_cpu == 4 and args_cpu[4]:find("compose.yaml$") ~= nil, vim.inspect(args_cpu))
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
check("up runs compose up -d", calls[1] and calls[1]:find("podman compose %-f .-compose.yaml up %-d") ~= nil, calls[1])
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

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
vim.cmd(failures == 0 and "qa!" or "cq!")

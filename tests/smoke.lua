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

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
vim.cmd(failures == 0 and "qa!" or "cq!")

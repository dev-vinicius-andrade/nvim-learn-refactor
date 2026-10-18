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
session.stop(true)
check("stop clears session", session.current == nil)

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
vim.cmd(failures == 0 and "qa!" or "cq!")

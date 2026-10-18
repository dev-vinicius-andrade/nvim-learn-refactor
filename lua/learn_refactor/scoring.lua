local config = require("learn_refactor.config")

local M = {}

--- true if check condition holds, false if not, nil on bad pattern
function M.run_check(check, text)
  if type(check) ~= "table" or type(check.pattern) ~= "string" then
    return nil
  end
  local ok, idx = pcall(vim.fn.match, text, "\\v\\C" .. check.pattern)
  if not ok then
    return nil
  end
  local found = idx >= 0
  if check.type == "absent" then
    return not found
  end
  return found
end

local function nonblank_lines(text)
  local n = 0
  for l in (text .. "\n"):gmatch("(.-)\n") do
    if l:match("%S") then
      n = n + 1
    end
  end
  return n
end

--- Run the challenge's hidden tests against `code` in a throwaway directory.
--- cb(nil) when tests are unavailable/disabled, else cb(passed:boolean, output:string)
function M.run_tests(ch, code, cb)
  local opts = config.options
  local lang = opts.languages[ch.language] or {}
  if not (opts.run_tests and lang.test and lang.ext and type(ch.tests) == "table"
      and type(ch.tests.code) == "string" and type(code) == "string") then
    return cb(nil)
  end
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local test_file = "hidden_test." .. lang.ext
  vim.fn.writefile(vim.split(code, "\n", { plain = true }), dir .. "/main." .. lang.ext)
  vim.fn.writefile(vim.split(ch.tests.code, "\n", { plain = true }), dir .. "/" .. test_file)
  local escaped = vim.fn.shellescape(test_file)
  local cmd = lang.test:gsub("{test}", function()
    return escaped
  end)
  local ok, err = pcall(vim.system, { vim.o.shell, vim.o.shellcmdflag, cmd },
    { text = true, timeout = 15000, cwd = dir }, vim.schedule_wrap(function(res)
      vim.fn.delete(dir, "rf")
      cb(res.code == 0, (res.stdout or "") .. (res.stderr or ""))
    end))
  if not ok then
    vim.fn.delete(dir, "rf")
    cb(nil, tostring(err))
  end
end

local function line(list, label, pts, ok)
  list[#list + 1] = { label = label, points = pts, ok = ok }
end

--- Score a finished attempt.
--- metrics: {seconds, keys, arrows, mouse, spam, hints, errors (diagnostics or nil)}
--- cb(result)
function M.score(ch, text, metrics, cb)
  local function empty(reason)
    cb({ lines = {}, points = 0, max_points = 0, tag_results = {}, note = reason })
  end

  if text == ch.code then
    return empty("You did not change anything - 0 points.")
  end
  local ratio = config.options.min_code_ratio or 0
  if nonblank_lines(text) < ratio * nonblank_lines(ch.code) then
    return empty("Most of the code was deleted instead of refactored - 0 points.")
  end

  M.run_tests(ch, text, function(tests_ok, test_out)
    local lines, total, max = {}, 0, 0
    local tag_results = {}
    -- behaviour broken -> refactor credit is halved (a "fix" that breaks tests is not a fix)
    local factor = (tests_ok == false) and 0.5 or 1

    local function award(label, pts, ok, tag)
      local earned = ok and math.floor(pts * factor) or 0
      max = max + pts
      total = total + earned
      line(lines, label, earned, ok)
      tag_results[tag] = tag_results[tag] or { seen = 0, passed = 0 }
      tag_results[tag].seen = tag_results[tag].seen + 1
      tag_results[tag].passed = tag_results[tag].passed + (ok and 1 or 0)
    end

    for _, bug in ipairs(ch.bugs or {}) do
      award("Bug: " .. (bug.description or bug.id), bug.points or 30, M.run_check(bug.fixed, text) == true, "bug")
    end
    for _, st in ipairs(ch.standards or {}) do
      award(st.name or st.id, st.points or 10, M.run_check(st.check, text) == true, st.tag or "style")
    end

    if tests_ok ~= nil then
      max = max + 40
      if tests_ok then
        total = total + 40
        line(lines, "Behaviour verified by hidden tests", 40, true)
      else
        line(lines, "Hidden tests FAILED: refactor credit halved", 0, false)
      end
    end

    -- terminal skill modifiers
    local par = config.options.par_seconds[ch.complexity] or 300
    local time_bonus = 0
    if metrics.seconds and metrics.seconds < par then
      time_bonus = math.floor(15 * (1 - metrics.seconds / par))
    end
    if time_bonus > 0 then
      total = total + time_bonus
      line(lines, string.format("Speed bonus (par %ds)", par), time_bonus, true)
    end
    max = max + 15

    local sloppy = (metrics.arrows or 0) + (metrics.mouse or 0) + (metrics.spam or 0)
    local penalty = math.min(15, sloppy)
    if penalty > 0 then
      total = total - penalty
      line(lines, string.format("Inefficient input (%d arrows/mouse/hjkl spam)", sloppy), -penalty, false)
    else
      total = total + 10
      line(lines, "Clean motions (no arrows, mouse or hjkl spam)", 10, true)
    end
    max = max + 10

    if (metrics.hints or 0) > 0 then
      local cost = metrics.hints * config.options.hint_cost
      total = total - cost
      line(lines, string.format("Hints used (%d)", metrics.hints), -cost, false)
    end

    if metrics.errors ~= nil then
      local ok = metrics.errors == 0
      max = max + 10
      total = total + (ok and 10 or 0)
      line(lines, "No LSP errors", ok and 10 or 0, ok)
    end

    cb({
      lines = lines,
      points = math.max(0, total),
      max_points = max,
      tag_results = tag_results,
      time_bonus = time_bonus,
      tests_ok = tests_ok,
      test_output = test_out,
    })
  end)
end

--- fold results into the persistent profile used for adaptive generation
function M.update_profile(ch, result)
  local store = require("learn_refactor.store")
  local p = store.profile()
  p.total_points = (p.total_points or 0) + result.points
  p.tags = p.tags or {}
  for tag, r in pairs(result.tag_results or {}) do
    local t = p.tags[tag] or { seen = 0, passed = 0 }
    t.seen = t.seen + r.seen
    t.passed = t.passed + r.passed
    p.tags[tag] = t
  end
  p.languages = p.languages or {}
  local l = p.languages[ch.language] or { played = 0 }
  l.played = l.played + 1
  p.languages[ch.language] = l
  store.save_profile(p)
end

return M

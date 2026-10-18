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

local function line(list, label, pts, ok)
  list[#list + 1] = { label = label, points = pts, ok = ok }
end

--- Score a finished attempt.
--- metrics: {seconds, keys, arrows, mouse, spam, hints, errors (diagnostics or nil)}
--- cb(result)
function M.score(ch, text, metrics, cb)
  local lines, total, max = {}, 0, 0
  local tag_results = {}

  local changed = text ~= ch.code
  if not changed then
    return cb({ lines = {}, points = 0, max_points = 0, unchanged = true, tag_results = {} })
  end

  for _, bug in ipairs(ch.bugs or {}) do
    local pts = bug.points or 30
    local ok = M.run_check(bug.fixed, text) == true
    max = max + pts
    total = total + (ok and pts or 0)
    line(lines, "Bug: " .. (bug.description or bug.id), ok and pts or 0, ok)
    tag_results["bug"] = tag_results["bug"] or { seen = 0, passed = 0 }
    tag_results["bug"].seen = tag_results["bug"].seen + 1
    tag_results["bug"].passed = tag_results["bug"].passed + (ok and 1 or 0)
  end

  for _, st in ipairs(ch.standards or {}) do
    local pts = st.points or 10
    local ok = M.run_check(st.check, text) == true
    max = max + pts
    total = total + (ok and pts or 0)
    line(lines, st.name or st.id, ok and pts or 0, ok)
    local tag = st.tag or "style"
    tag_results[tag] = tag_results[tag] or { seen = 0, passed = 0 }
    tag_results[tag].seen = tag_results[tag].seen + 1
    tag_results[tag].passed = tag_results[tag].passed + (ok and 1 or 0)
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

  local function done(extra)
    if extra then
      total = total + extra.points
      max = max + 40
      line(lines, extra.label, extra.points, extra.ok)
    end
    cb({
      lines = lines,
      points = math.max(0, total),
      max_points = max,
      tag_results = tag_results,
      time_bonus = time_bonus,
    })
  end

  if ch.run_cmd and metrics.file then
    local escaped = vim.fn.shellescape(metrics.file)
    local cmd = ch.run_cmd:gsub("{file}", function()
      return escaped
    end)
    vim.system({ vim.o.shell, vim.o.shellcmdflag, cmd }, { text = true, timeout = 15000, cwd = vim.fs.dirname(metrics.file) },
      vim.schedule_wrap(function(res)
        local ok = res.code == 0
        done({ label = ok and "Behaviour verified (run_cmd passed)" or "Behaviour check failed (run_cmd)", points = ok and 40 or 0, ok = ok })
      end))
  else
    done()
  end
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

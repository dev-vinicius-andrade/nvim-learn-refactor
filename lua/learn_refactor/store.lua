-- JSON file storage: challenges/<id>.json, history.json, profile.json, workspace/<id>/
local config = require("learn_refactor.config")

local M = {}

local function dir(sub)
  local p = config.options.data_dir .. (sub and ("/" .. sub) or "")
  vim.fn.mkdir(p, "p")
  return p
end

local function read_json(path, default)
  local f = io.open(path, "r")
  if not f then
    return default
  end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    return default
  end
  return data
end

local function write_json(path, data)
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(vim.json.encode(data))
  f:close()
  return true
end

function M.new_id()
  return os.date("%Y%m%d-%H%M%S") .. "-" .. string.format("%04x", math.random(0, 0xffff))
end

function M.save_challenge(ch)
  if type(ch.id) ~= "string" or not ch.id:match("^[%w%-_]+$") then
    ch.id = M.new_id() -- never use an untrusted id as a path component
  end
  ch.created_at = ch.created_at or os.time()
  return write_json(dir("challenges") .. "/" .. ch.id .. ".json", ch), ch
end

function M.load_challenge(id)
  return read_json(dir("challenges") .. "/" .. id .. ".json")
end

--- list saved challenges, newest first; optional filter {language=, complexity=}
function M.list_challenges(filter)
  filter = filter or {}
  local out = {}
  for _, path in ipairs(vim.fn.glob(dir("challenges") .. "/*.json", false, true)) do
    local ch = read_json(path)
    if ch and (not filter.language or ch.language == filter.language)
      and (not filter.complexity or ch.complexity == filter.complexity) then
      out[#out + 1] = ch
    end
  end
  table.sort(out, function(a, b)
    return (a.created_at or 0) > (b.created_at or 0)
  end)
  return out
end

function M.history()
  return read_json(dir() .. "/history.json", {})
end

function M.append_history(entry)
  local h = M.history()
  h[#h + 1] = entry
  write_json(dir() .. "/history.json", h)
end

--- Challenges never finished (stopped, or generated but not completed), most recently touched first.
--- `languages`: optional set { name = true }. Returns list of { ch = challenge, seconds = clock at last stop }.
function M.unfinished(languages)
  local finished, activity, seconds = {}, {}, {}
  for _, h in ipairs(M.history()) do
    if h.status == "finished" then
      finished[h.challenge_id] = true
    end
    activity[h.challenge_id] = math.max(activity[h.challenge_id] or 0, h.at or 0)
    if h.status == "stopped" then
      seconds[h.challenge_id] = h.seconds
    end
  end
  local list = {}
  for _, ch in ipairs(M.list_challenges()) do
    if not finished[ch.id] and (not languages or languages[ch.language]) then
      list[#list + 1] = { ch = ch, seconds = seconds[ch.id], at = activity[ch.id] or ch.created_at or 0 }
    end
  end
  table.sort(list, function(a, b)
    return a.at > b.at
  end)
  return list
end

function M.profile()
  return read_json(dir() .. "/profile.json", { total_points = 0, tags = {}, languages = {} })
end

--- accumulate motion-coach counters (vertical, horizontal, words, xs, bs, arrows, mouse)
function M.add_habits(stats)
  local p = M.profile()
  p.habits = p.habits or {}
  for k, n in pairs(stats) do
    if type(n) == "number" and n > 0 then
      p.habits[k] = (p.habits[k] or 0) + n
    end
  end
  M.save_profile(p)
end

function M.save_profile(p)
  return write_json(dir() .. "/profile.json", p)
end

function M.workspace(id)
  return dir("workspace/" .. id)
end

return M

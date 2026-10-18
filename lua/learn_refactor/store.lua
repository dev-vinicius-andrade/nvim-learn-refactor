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
  ch.id = ch.id or M.new_id()
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

function M.profile()
  return read_json(dir() .. "/profile.json", { total_points = 0, tags = {}, languages = {} })
end

function M.save_profile(p)
  return write_json(dir() .. "/profile.json", p)
end

function M.workspace(id)
  return dir("workspace/" .. id)
end

return M

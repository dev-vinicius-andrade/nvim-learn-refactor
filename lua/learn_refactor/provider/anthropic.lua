local config = require("learn_refactor.config")

local M = {}

--- cb(text|nil, err|nil)
function M.request(prompt, cb, route)
  local o = config.options.anthropic
  route = route or {}
  local key = os.getenv(o.api_key_env)
  if not key or key == "" then
    return cb(nil, o.api_key_env .. " not set")
  end
  if vim.fn.executable("curl") ~= 1 then
    return cb(nil, "curl not found")
  end
  local body = vim.json.encode({
    model = route.model or o.model,
    max_tokens = o.max_tokens,
    messages = { { role = "user", content = prompt } },
  })
  vim.system({
    "curl", "-sS", "--max-time", tostring(o.timeout),
    "https://api.anthropic.com/v1/messages",
    "-H", "content-type: application/json",
    "-H", "anthropic-version: 2023-06-01",
    "-H", "x-api-key: " .. key,
    "--data-binary", "@-",
  }, { stdin = body, text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return cb(nil, "curl failed: " .. (res.stderr or res.code))
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok then
      return cb(nil, "bad API response")
    end
    if data.error then
      return cb(nil, "API error: " .. (data.error.message or "unknown"))
    end
    local parts = {}
    for _, block in ipairs(data.content or {}) do
      if block.type == "text" then
        parts[#parts + 1] = block.text
      end
    end
    cb(table.concat(parts))
  end))
end

return M

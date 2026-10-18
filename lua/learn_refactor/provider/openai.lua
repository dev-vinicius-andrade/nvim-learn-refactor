-- Any OpenAI-compatible /chat/completions endpoint: Ollama, LM Studio, OpenRouter, Groq, GitHub Models, ...
local config = require("learn_refactor.config")

local M = {}

--- cb(text|nil, err|nil); route may override `model`
local request

function M.request(prompt, cb, route)
  local o = config.options.openai
  route = route or {}
  local ollama = require("learn_refactor.ollama")
  if config.options.ollama.auto_start and ollama.is_local(route.base_url or o.base_url) then
    return ollama.ensure(function(ok, err)
      if not ok then
        return cb(nil, err)
      end
      request(prompt, cb, route)
    end)
  end
  request(prompt, cb, route)
end

request = function(prompt, cb, route)
  local o = config.options.openai
  if vim.fn.executable("curl") ~= 1 then
    return cb(nil, "curl not found")
  end
  -- a model set for the managed Ollama is the default when openai.model is unset
  local model = route.model or o.model or config.options.ollama.model
  if not model or model == "" then
    return cb(nil, "openai.model not set")
  end
  local args = {
    "curl", "-sS", "--max-time", tostring(o.timeout),
    (route.base_url or o.base_url):gsub("/+$", "") .. "/chat/completions",
    "-H", "content-type: application/json",
  }
  local env = route.api_key_env or o.api_key_env
  if env then
    local key = os.getenv(env)
    if not key or key == "" then
      return cb(nil, env .. " not set")
    end
    vim.list_extend(args, { "-H", "authorization: Bearer " .. key })
  end
  vim.list_extend(args, { "--data-binary", "@-" })

  local payload = {
    model = model,
    max_tokens = o.max_tokens,
    messages = { { role = "user", content = prompt } },
  }
  local json_mode = o.json_mode
  if json_mode == "auto" then
    json_mode = require("learn_refactor.ollama").is_local(route.base_url or o.base_url)
  end
  if json_mode then
    payload.response_format = { type = "json_object" }
  end
  local body = vim.json.encode(payload)
  vim.system(args, { stdin = body, text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return cb(nil, "curl failed: " .. (res.stderr or res.code))
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or type(data) ~= "table" then
      return cb(nil, "bad API response")
    end
    if data.error then
      local e = data.error
      return cb(nil, "API error: " .. (type(e) == "table" and e.message or tostring(e)))
    end
    local msg = data.choices and data.choices[1] and data.choices[1].message
    if not msg or type(msg.content) ~= "string" then
      return cb(nil, "API returned no content")
    end
    if data.choices[1].finish_reason == "length" then
      return cb(nil, "reply truncated (finish_reason=length): raise openai.max_tokens / the server context size")
    end
    cb(msg.content)
  end))
end

return M

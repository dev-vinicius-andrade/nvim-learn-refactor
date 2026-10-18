local M = {}

function M.check()
  local config = require("learn_refactor.config")
  local o = config.options
  vim.health.start("learn-refactor")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim 0.10+ required (vim.system, vim.uv)")
  end
  if o.provider == "anthropic" then
    if vim.fn.executable("curl") == 1 then
      vim.health.ok("curl found")
    else
      vim.health.error("curl not found (needed for provider = anthropic)")
    end
    local key = os.getenv(o.anthropic.api_key_env)
    if key and key ~= "" then
      vim.health.ok(o.anthropic.api_key_env .. " is set")
    else
      vim.health.warn(o.anthropic.api_key_env .. " not set - will fall back to saved/built-in challenges")
    end
  elseif o.provider == "openai" then
    if vim.fn.executable("curl") == 1 then
      vim.health.ok("curl found")
    else
      vim.health.error("curl not found (needed for provider = openai)")
    end
    if o.openai.model then
      vim.health.ok("openai model: " .. o.openai.model .. " @ " .. o.openai.base_url)
    else
      vim.health.error("openai.model not set")
    end
  else
    vim.health.info("provider = " .. o.provider)
  end
  for cx, r in pairs(o.routes or {}) do
    vim.health.info(string.format("route %s -> %s %s", cx, r.provider or o.provider, r.model or "(default model)"))
  end
  vim.health.info("data dir: " .. o.data_dir)
  if vim.o.mouse == "" then
    vim.health.info("'mouse' is empty: the control bar is keyboard-only (use :RefactorPlay etc.)")
  end
end

return M

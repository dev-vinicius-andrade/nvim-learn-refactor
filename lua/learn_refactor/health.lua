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
  else
    vim.health.info("provider = " .. o.provider)
  end
  vim.health.info("data dir: " .. o.data_dir)
  if vim.o.mouse == "" then
    vim.health.info("'mouse' is empty: the control bar is keyboard-only (use :RefactorPlay etc.)")
  end
end

return M

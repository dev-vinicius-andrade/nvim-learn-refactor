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
  if o.provider == "openai" or o.ollama.auto_start then
    local ollama = require("learn_refactor.ollama")
    local rt = ollama.runtime()
    if rt then
      vim.health.ok("container runtime: " .. rt)
      local gpu = ollama.use_gpu(rt)
      if gpu == "missing-cdi" then
        vim.health.error("ollama.gpu = true but no NVIDIA CDI spec", "sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml")
      else
        vim.health.info("ollama GPU override: " .. tostring(gpu == true))
      end
    elseif o.ollama.auto_start then
      vim.health.error("ollama.auto_start needs podman or docker in PATH")
    end
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

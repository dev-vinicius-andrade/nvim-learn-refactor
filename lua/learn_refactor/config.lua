local M = {}

M.defaults = {
  -- where challenges, workspaces, history and profile are saved
  data_dir = vim.fn.stdpath("data") .. "/learn-refactor",
  languages = {
    -- `test` = command that runs the hidden test file ({test}); omit to disable tests for that language.
    -- Tests are model-written code executed on YOUR machine (see README, "Security").
    lua = { ext = "lua", test = "lua {test}" },
    python = { ext = "py", test = "python {test}" },
    javascript = { ext = "js", test = "node {test}" },
    typescript = { ext = "ts" },
    go = { ext = "go" },
    rust = { ext = "rs" },
    c = { ext = "c" },
    cpp = { ext = "cpp" },
    java = { ext = "java" },
    csharp = { ext = "cs" },
    ruby = { ext = "rb", test = "ruby {test}" },
    bash = { ext = "sh" },
  },
  -- run model-written hidden tests (validated against the model's reference solution before use)
  run_tests = true,
  -- anti-gaming: fewer non-blank lines than this fraction of the original scores 0
  min_code_ratio = 0.35,
  complexities = { "easy", "medium", "hard", "expert" },
  -- "anthropic" calls the API with curl (needs api key env var); "static" uses built-in seeds
  provider = "anthropic",
  anthropic = {
    api_key_env = "ANTHROPIC_API_KEY",
    model = "claude-sonnet-5-5",
    max_tokens = 4096,
    timeout = 90,
  },
  -- "openai" = any OpenAI-compatible endpoint (Ollama, LM Studio, OpenRouter, Groq, ...)
  openai = {
    base_url = "http://localhost:11434/v1",
    model = nil, -- required when used, e.g. "qwen2.5-coder:14b"
    api_key_env = nil, -- e.g. "OPENROUTER_API_KEY"; nil = no auth header
    max_tokens = 4096,
    timeout = 180,
  },
  -- Local Ollama in a container (podman or docker compose), see :RefactorOllama and docker/compose*.yaml.
  -- With provider = "openai" and base_url on `port`, `auto_start = true` brings it up on demand.
  ollama = {
    runtime = nil, -- "podman" | "docker"; nil = first one found
    gpu = "auto", -- "auto" | true | false; GPU needs nvidia-container-toolkit (podman: CDI spec)
    model = "qwen2.5-coder:14b", -- ~9 GB, fits a 12-16 GB GPU; try :7b for 8 GB or less
    port = 11434,
    auto_start = false,
  },
  -- optional per-complexity override; any key falls back to the global provider/model, e.g.
  -- routes = { easy = { provider = "anthropic", model = "claude-haiku-5-5" },
  --            expert = { provider = "anthropic", model = "claude-sonnet-5-5" } }
  routes = {},
  -- fall back to saved library / seeds when generation fails
  fallback = true,
  -- seconds a perfect-pace run is allowed per complexity (time bonus)
  par_seconds = { easy = 180, medium = 300, hard = 480, expert = 720 },
  hint_cost = 5,
  -- floating control bar with clickable play / pause / stop / finish
  control_bar = true,
  -- `false` to skip default keymaps (e.g. when lazy.nvim `keys` defines them), or override per action.
  -- <leader>R (capital) avoids clashing with common <leader>r rename/restart LSP mappings.
  keymaps = {
    start = "<leader>Rr",
    library = "<leader>Rl",
    play = "<leader>Rp",
    pause = "<leader>RP",
    stop = "<leader>Rs",
    finish = "<leader>Rf",
    hint = "<leader>Rh",
    config_tips = "<leader>Rt",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  return M.options
end

return M

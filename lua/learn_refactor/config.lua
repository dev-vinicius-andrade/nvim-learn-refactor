local M = {}

M.defaults = {
  -- where challenges, workspaces, history and profile are saved
  data_dir = vim.fn.stdpath("data") .. "/learn-refactor",
  languages = {
    lua = { ext = "lua", run = "lua {file}" },
    python = { ext = "py", run = "python {file}" },
    javascript = { ext = "js", run = "node {file}" },
    typescript = { ext = "ts" },
    go = { ext = "go" },
    rust = { ext = "rs" },
    c = { ext = "c" },
    cpp = { ext = "cpp" },
    java = { ext = "java" },
    csharp = { ext = "cs" },
    ruby = { ext = "rb", run = "ruby {file}" },
    bash = { ext = "sh", run = "bash {file}" },
  },
  complexities = { "easy", "medium", "hard", "expert" },
  -- "anthropic" calls the API with curl (needs api key env var); "static" uses built-in seeds
  provider = "anthropic",
  anthropic = {
    api_key_env = "ANTHROPIC_API_KEY",
    model = "claude-sonnet-5-5",
    max_tokens = 4096,
    timeout = 90,
  },
  -- fall back to saved library / seeds when generation fails
  fallback = true,
  -- seconds a perfect-pace run is allowed per complexity (time bonus)
  par_seconds = { easy = 180, medium = 300, hard = 480, expert = 720 },
  hint_cost = 5,
  -- floating control bar with clickable play / pause / stop / finish
  control_bar = true,
  -- set to false to skip default keymaps; <leader>r prefix
  keymaps = {
    play = "<leader>rp",
    pause = "<leader>rP",
    stop = "<leader>rs",
    finish = "<leader>rf",
    hint = "<leader>rh",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  return M.options
end

return M

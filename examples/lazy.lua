-- lazy.nvim / LazyVim spec. Drop into lua/plugins/learn-refactor.lua (LazyVim and most lazy.nvim setups
-- import that folder), or add the table to your own `require("lazy").setup({...})`.
return {
  {
    "dev-vinicius-andrade/nvim-learn-refactor",
    -- dir = "~/path/to/nvim-learn-refactor", -- use this instead of the line above for a local checkout
    cmd = {
      "Refactor", "RefactorPlay", "RefactorPause", "RefactorStop", "RefactorFinish",
      "RefactorHint", "RefactorLibrary", "RefactorStats", "RefactorConfigTips", "RefactorMenu", "RefactorOllama", "RefactorContinue",
    },
    -- lazy-load on first use; `keys` also registers the mappings (and shows them in which-key)
    keys = {
      { "<leader>Rm", "<cmd>RefactorMenu<cr>", desc = "Refactor: menu" },
      { "<leader>Rc", "<cmd>RefactorContinue<cr>", desc = "Refactor: continue unfinished" },
      { "<leader>Rr", "<cmd>Refactor<cr>", desc = "Refactor: start challenge" },
      { "<leader>Rl", "<cmd>RefactorLibrary<cr>", desc = "Refactor: saved challenges" },
      { "<leader>Rp", "<cmd>RefactorPlay<cr>", desc = "Refactor: play / resume" },
      { "<leader>RP", "<cmd>RefactorPause<cr>", desc = "Refactor: pause" },
      { "<leader>Rs", "<cmd>RefactorStop<cr>", desc = "Refactor: stop" },
      { "<leader>Rf", "<cmd>RefactorFinish<cr>", desc = "Refactor: finish & score" },
      { "<leader>Rh", "<cmd>RefactorHint<cr>", desc = "Refactor: hint" },
      { "<leader>Rt", "<cmd>RefactorConfigTips<cr>", desc = "Refactor: setup tips" },
    },
    opts = {
      keymaps = false, -- `keys` above owns the mappings
      -- provider = "openai",
      -- openai = { model = "qwen2.5-coder:14b" },
    },
  },
  { "folke/which-key.nvim", optional = true, opts = { spec = { { "<leader>R", group = "refactor practice" } } } },
}

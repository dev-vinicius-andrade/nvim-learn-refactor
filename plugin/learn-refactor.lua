if vim.g.loaded_learn_refactor then
  return
end
vim.g.loaded_learn_refactor = true

local function lr()
  return require("learn_refactor")
end

vim.api.nvim_create_user_command("Refactor", function(o)
  local a = o.fargs
  lr().start({ language = a[1], complexity = a[2], library = a[3] == "library" })
end, {
  nargs = "*",
  desc = "Start a refactoring challenge: :Refactor [language] [complexity] [library]",
  complete = function(_, line)
    local n = #vim.split(line, "%s+") - 1
    if n == 1 then
      local names = vim.tbl_keys(require("learn_refactor.config").options.languages)
      table.sort(names)
      return names
    elseif n == 2 then
      return require("learn_refactor.config").options.complexities
    elseif n == 3 then
      return { "library" }
    end
  end,
})

vim.api.nvim_create_user_command("RefactorOllama", function(o)
  require("learn_refactor.ollama").command(o.fargs[1])
end, {
  nargs = "?",
  desc = "Manage the local Ollama container: up|down|status|pull",
  complete = function()
    return { "up", "down", "status", "pull" }
  end,
})

local simple = {
  RefactorPlay = { "play", "Start / resume the clock" },
  RefactorPause = { "pause", "Pause the session (buffer locked)" },
  RefactorStop = { "stop", "Abort the session without scoring" },
  RefactorFinish = { "finish", "Finish and score the session" },
  RefactorHint = { "hint", "Reveal a hint (costs points)" },
  RefactorContinue = { "continue", "Continue the latest unfinished challenge" },
  RefactorLibrary = { "library", "Pick a saved challenge" },
  RefactorMenu = { "menu", "Floating action menu (play, pause, finish, ...)" },
  RefactorConfigTips = { "config_tips", "Suggest improvements to your Neovim setup" },
  RefactorStats ={ "stats", "Show points and weak topics" },
}
for name, def in pairs(simple) do
  vim.api.nvim_create_user_command(name, function()
    lr()[def[1]]()
  end, { desc = def[2] })
end

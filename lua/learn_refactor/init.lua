local config = require("learn_refactor.config")
local session = require("learn_refactor.session")

local M = {}

function M.setup(opts)
  config.setup(opts)
  for action, lhs in pairs(config.options.keymaps or {}) do
    if lhs and M[action] then
      vim.keymap.set("n", lhs, M[action], { desc = "LearnRefactor " .. action })
    end
  end
end

M.play = session.play
M.pause = session.pause
M.stop = function()
  session.stop()
end
M.finish = session.finish
M.hint = session.hint
M.statusline = session.statusline

--- :Refactor [language] [complexity] [library]
function M.start(args)
  local ui = require("learn_refactor.ui")
  args = args or {}
  if args.language and args.complexity then
    if args.library then
      return ui.library(args.language, args.complexity)
    end
    return ui.generate(args.language, args.complexity)
  end
  ui.menu(args)
end

function M.library()
  require("learn_refactor.ui").menu({ library = true })
end

function M.stats()
  require("learn_refactor.ui").stats()
end

return M

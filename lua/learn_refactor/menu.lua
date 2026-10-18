-- State-aware floating action menu (:RefactorMenu): only offers what is valid right now.
local session = require("learn_refactor.session")

local M = {}

local function lr()
  return require("learn_refactor")
end

--- items for the current state: { key, label, run }
function M.items()
  local s = session.current
  local ui = function()
    return require("learn_refactor.ui")
  end
  local ollama = function()
    return require("learn_refactor.ollama")
  end
  if not s then
    return {
      { "n", "New challenge", function() lr().start() end },
      { "l", "Saved challenges", function() lr().library() end },
      { "g", "Stats", function() ui().stats() end },
      { "t", "Setup tips", function() ui().config_tips() end },
      { "u", "Ollama: start", function() ollama().command("up") end },
      { "d", "Ollama: stop", function() ollama().command("down") end },
      { "i", "Ollama: status", function() ollama().command("status") end },
    }
  end
  local stop = { "s", "Stop (no score)", function() lr().stop() end }
  if s.state == "ready" then
    return { { "p", "Play: start the clock", function() lr().play() end }, stop }
  elseif s.state == "running" then
    return {
      { "z", "Pause", function() lr().pause() end },
      { "f", "Finish and score", function() lr().finish() end },
      { "h", "Hint (costs points)", function() lr().hint() end },
      stop,
    }
  end
  return { -- paused
    { "p", "Resume", function() lr().play() end },
    { "f", "Finish and score", function() lr().finish() end },
    stop,
  }
end

local function title()
  local s = session.current
  if not s then
    return " Refactor "
  end
  local sec = session.elapsed()
  return string.format(" Refactor - %s %02d:%02d ", s.state, math.floor(sec / 60), math.floor(sec % 60))
end

function M.open()
  local items = M.items()
  local prev = vim.api.nvim_get_current_win()
  local lines, width = {}, vim.fn.strdisplaywidth(title())
  for _, it in ipairs(items) do
    local l = string.format("  %s   %s", it[1], it[2])
    lines[#lines + 1] = l
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  local footer = " j/k move  <CR> select  q close "
  width = math.max(width, vim.fn.strdisplaywidth(footer))
  width = math.min(width, vim.o.columns - 4)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = title(), title_pos = "center", footer = footer, footer_pos = "center",
    width = width, height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "CursorLine:PmenuSel,NormalFloat:NormalFloat"

  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(prev) then
      vim.api.nvim_set_current_win(prev)
    end
  end
  local function run(it)
    close()
    vim.schedule(it[3])
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  for _, it in ipairs(items) do
    map(it[1], function() run(it) end)
  end
  map("<CR>", function()
    run(items[vim.api.nvim_win_get_cursor(win)[1]])
  end)
  for _, lhs in ipairs({ "q", "<Esc>", "<C-c>" }) do
    map(lhs, close)
  end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

return M

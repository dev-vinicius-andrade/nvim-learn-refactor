-- State-aware floating action menu (:RefactorMenu): only offers what is valid right now, and shows
-- how to trigger each action without the menu (your real mappings + the command).
local session = require("learn_refactor.session")

local M = {}

local NS = vim.api.nvim_create_namespace("learn_refactor_menu")

local function lr()
  return require("learn_refactor")
end

local function ui()
  return require("learn_refactor.ui")
end

local function ollama()
  return require("learn_refactor.ollama")
end

--- items for the current state:
--- { key = menu shortcut, label, cmd = ex command, action = learn_refactor function name, run }
function M.items()
  local s = session.current
  local function item(key, label, cmd, action, run)
    return { key = key, label = label, cmd = cmd, action = action, run = run }
  end
  if not s then
    return {
      item("n", "New challenge", "Refactor", "start", function() lr().start() end),
      item("l", "Saved challenges", "RefactorLibrary", "library", function() lr().library() end),
      item("g", "Stats", "RefactorStats", "stats", function() ui().stats() end),
      item("t", "Setup tips", "RefactorConfigTips", "config_tips", function() ui().config_tips() end),
      item("u", "Ollama: start", "RefactorOllama up", nil, function() ollama().command("up") end),
      item("d", "Ollama: stop", "RefactorOllama down", nil, function() ollama().command("down") end),
      item("i", "Ollama: status", "RefactorOllama status", nil, function() ollama().command("status") end),
    }
  end
  local stop = item("s", "Stop (no score)", "RefactorStop", "stop", function() lr().stop() end)
  if s.state == "ready" then
    return { item("p", "Play: start the clock", "RefactorPlay", "play", function() lr().play() end), stop }
  elseif s.state == "running" then
    return {
      item("z", "Pause", "RefactorPause", "pause", function() lr().pause() end),
      item("f", "Finish and score", "RefactorFinish", "finish", function() lr().finish() end),
      item("h", "Hint (costs points)", "RefactorHint", "hint", function() lr().hint() end),
      stop,
    }
  end
  return { -- paused
    item("p", "Resume", "RefactorPlay", "play", function() lr().play() end),
    item("f", "Finish and score", "RefactorFinish", "finish", function() lr().finish() end),
    stop,
  }
end

local function normalize_rhs(rhs)
  rhs = (rhs or ""):lower():gsub("^<cmd>", ""):gsub("^:", ""):gsub("<cr>$", ""):gsub("%s+$", "")
  return rhs
end

--- "<Space>Rp" / " Rp" -> "<leader>Rp"
local function display_lhs(lhs)
  local leader = vim.g.mapleader or "\\"
  for _, prefix in ipairs({ leader == " " and "<Space>" or leader, leader }) do
    if prefix ~= "" and lhs:sub(1, #prefix) == prefix then
      return "<leader>" .. lhs:sub(#prefix + 1)
    end
  end
  return lhs
end

--- global normal-mode mappings that run a command or one of our setup() actions
--- returns { by_cmd = {normalized cmd -> lhs}, by_action = {action -> lhs} }
function M.mappings()
  local by_cmd, by_action = {}, {}
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    local lhs = display_lhs(m.lhs)
    if m.rhs and m.rhs ~= "" then
      local key = normalize_rhs(m.rhs)
      by_cmd[key] = by_cmd[key] or lhs
    end
    local action = (m.desc or ""):match("^LearnRefactor (%S+)$")
    if action then
      by_action[action] = by_action[action] or lhs
    end
  end
  return { by_cmd = by_cmd, by_action = by_action }
end

--- the key that opens this menu (from the user's real mappings), or nil
function M.key()
  local maps = M.mappings()
  return maps.by_cmd["refactormenu"] or maps.by_action["menu"]
end

local function binding_for(it, maps)
  return maps.by_cmd[it.cmd:lower()] or (it.action and maps.by_action[it.action]) or nil
end

local function title()
  local s = session.current
  if not s then
    return " Refactor "
  end
  local sec = session.elapsed()
  return string.format(" Refactor - %s %02d:%02d ", s.state, math.floor(sec / 60), math.floor(sec % 60))
end

--- build buffer lines + highlight spans; returns lines, spans, width
function M.render(items)
  local maps = M.mappings()
  local rows, any_binding = {}, false
  local label_w, bind_w = 0, 0
  for _, it in ipairs(items) do
    local b = binding_for(it, maps)
    any_binding = any_binding or b ~= nil
    rows[#rows + 1] = { it = it, bind = b or "-" }
    label_w = math.max(label_w, vim.fn.strdisplaywidth(it.label))
    bind_w = math.max(bind_w, vim.fn.strdisplaywidth(b or "-"))
  end

  local lines, spans = {}, {}
  local function span(row, from, to, hl)
    spans[#spans + 1] = { row - 1, from, to, hl }
  end
  lines[#lines + 1] = string.format("  %-" .. 3 .. "s %-" .. label_w .. "s  %-" .. bind_w .. "s  %s", "key", "action", "mapped to", "command")
  span(1, 0, -1, "Comment")
  for _, r in ipairs(rows) do
    local it = r.it
    local l = string.format("  %-3s %-" .. label_w .. "s  %-" .. bind_w .. "s  :%s", it.key, it.label, r.bind, it.cmd)
    lines[#lines + 1] = l
    local row = #lines
    span(row, 2, 3, "Special")
    local bstart = 2 + 3 + 1 + label_w + 2
    span(row, bstart, bstart + #r.bind, r.bind == "-" and "Comment" or "Identifier")
    span(row, bstart + bind_w + 2, -1, "Comment")
  end

  local n_items = #lines
  local help = { "", "  How to use this menu:" }
  help[#help + 1] = "  - press the letter in the first column, or j/k + Enter"
  help[#help + 1] = "  - q or Esc closes it without doing anything"
  help[#help + 1] = "  - \"mapped to\" is the key that does the same without the menu"
  local menu_key = maps.by_cmd["refactormenu"] or maps.by_action["menu"]
  help[#help + 1] = "  - reopen this menu: " .. (menu_key and (menu_key .. " or ") or "") .. ":RefactorMenu"
  local tip, habit = require("learn_refactor.tips").pick(require("learn_refactor.store").profile().habits)
  help[#help + 1] = ""
  help[#help + 1] = (habit and "  Tip for your habits: " or "  Tip: ") .. tip
  if not any_binding then
    help[#help + 1] = "  - no keys are mapped yet: add `keys = {...}` to your plugin spec (see README)"
  end
  for _, h in ipairs(help) do
    lines[#lines + 1] = h
    span(#lines, 0, -1, "Comment")
  end

  local width = vim.fn.strdisplaywidth(title())
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  return lines, spans, math.min(width, vim.o.columns - 4), n_items
end

function M.open()
  local items = M.items()
  local prev = vim.api.nvim_get_current_win()
  local lines, spans, width, n_items = M.render(items)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, sp in ipairs(spans) do
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, sp[1], sp[2], {
      end_row = sp[1], end_col = sp[3] >= 0 and sp[3] or #lines[sp[1] + 1], hl_group = sp[4],
    })
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = title(), title_pos = "center",
    width = width, height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "CursorLine:PmenuSel"
  vim.api.nvim_win_set_cursor(win, { 2, 0 }) -- row 1 is the column header

  -- selection is limited to the item rows (2 .. n_items); the rest is help text
  local function clamp()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local clamped = math.min(math.max(row, 2), n_items)
    if clamped ~= row then
      vim.api.nvim_win_set_cursor(win, { clamped, 0 })
    end
  end
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = clamp })

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
    vim.schedule(it.run)
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  for _, it in ipairs(items) do
    map(it.key, function() run(it) end)
  end
  map("<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if items[row - 1] then
      run(items[row - 1])
    end
  end)
  for _, lhs in ipairs({ "q", "<Esc>", "<C-c>" }) do
    map(lhs, close)
  end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

return M

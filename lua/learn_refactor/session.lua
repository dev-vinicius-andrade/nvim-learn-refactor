-- Session state machine: ready -> running <-> paused -> finished | stopped
local config = require("learn_refactor.config")
local store = require("learn_refactor.store")
local scoring = require("learn_refactor.scoring")

local M = {}

local NS = vim.api.nvim_create_namespace("learn_refactor_keys")
local AUGROUP = vim.api.nvim_create_augroup("LearnRefactor", { clear = true })
local ARROWS = { Up = true, Down = true, Left = true, Right = true }
local HJKL = { h = true, j = true, k = true, l = true }

---@type table|nil
M.current = nil

local function emit(name, data)
  vim.api.nvim_exec_autocmds("User", { pattern = "LearnRefactor" .. name, modeline = false, data = data })
end

local function now()
  return vim.uv.hrtime()
end

function M.elapsed()
  local s = M.current
  if not s then
    return 0
  end
  local total = s.elapsed_ns
  if s.state == "running" then
    total = total + (now() - s.started_ns)
  end
  return total / 1e9
end

local function fmt_time(sec)
  return string.format("%02d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

function M.statusline()
  local s = M.current
  if not s then
    return ""
  end
  local icon = ({ ready = "■", running = "▶", paused = "⏸" })[s.state] or ""
  return string.format("%s %s  keys:%d", icon, fmt_time(M.elapsed()), s.metrics.keys)
end

-- ── key tracking ────────────────────────────────────────────────────────────
local function on_key(_, typed)
  local s = M.current
  if not s or s.state ~= "running" or typed == "" then
    return
  end
  if vim.api.nvim_get_current_buf() ~= s.buf then
    return
  end
  local m = s.metrics
  m.keys = m.keys + 1
  local ok, key = pcall(vim.fn.keytrans, typed)
  if not ok then
    return
  end
  if #s.keylog < 20000 then
    s.keylog[#s.keylog + 1] = { key, vim.api.nvim_get_mode().mode }
  end
  local name = key:match("^<(%a+)>$")
  if name and ARROWS[name] then
    m.arrows = m.arrows + 1
  elseif key:find("Mouse", 1, true) and not key:find("MouseMove", 1, true) then
    m.mouse = m.mouse + 1
  end
  if HJKL[key] and vim.api.nvim_get_mode().mode == "n" then
    if s.last_key == key then
      s.streak = s.streak + 1
      if s.streak > 4 then
        m.spam = m.spam + 1
      end
    else
      s.streak = 1
    end
  else
    s.streak = 0
  end
  s.last_key = key
end

-- ── windows ─────────────────────────────────────────────────────────────────
local function scratch(lines)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  return b
end

local BAR_ITEMS = {
  { label = " ▶ Play ", action = "play" },
  { label = " ⏸ Pause ", action = "pause" },
  { label = " ■ Stop ", action = "stop" },
  { label = " ✔ Finish ", action = "finish" },
  { label = " ? Hint ", action = "hint" },
}

local function bar_text()
  local parts, spans, col = {}, {}, 0
  for _, it in ipairs(BAR_ITEMS) do
    local w = vim.fn.strdisplaywidth(it.label)
    spans[#spans + 1] = { from = col + 1, to = col + w, action = it.action }
    parts[#parts + 1] = it.label
    col = col + w + 1
  end
  local s = M.current
  local clock = s and (" " .. fmt_time(M.elapsed()) .. " ") or ""
  return table.concat(parts, "|") .. clock, spans
end

local function refocus()
  local s = M.current
  if s and s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_set_current_win(s.win)
  end
end

local function render_bar()
  local s = M.current
  if not s or not s.bar_buf or not vim.api.nvim_buf_is_valid(s.bar_buf) then
    return
  end
  local text, spans = bar_text()
  s.bar_spans = spans
  vim.bo[s.bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.bar_buf, 0, -1, false, { text })
  vim.bo[s.bar_buf].modifiable = false
end

local function open_bar()
  local s = M.current
  s.bar_buf = scratch({ "" })
  local text = bar_text()
  s.bar_win = vim.api.nvim_open_win(s.bar_buf, false, {
    relative = "editor",
    row = 0,
    col = math.max(0, vim.o.columns - vim.fn.strdisplaywidth(text) - 2),
    width = vim.fn.strdisplaywidth(text) + 1,
    height = 1,
    style = "minimal",
    border = "none",
    focusable = true,
    zindex = 60,
  })
  vim.wo[s.bar_win].winhighlight = "Normal:StatusLine"
  render_bar()
  vim.keymap.set("n", "<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    for _, sp in ipairs(M.current and M.current.bar_spans or {}) do
      if pos.wincol >= sp.from and pos.wincol <= sp.to then
        refocus()
        M[sp.action]()
        return
      end
    end
    refocus()
  end, { buffer = s.bar_buf, silent = true })
end

local function open_info()
  local s = M.current
  local ch = s.ch
  local lines = {
    string.format("%s  [%s / %s]", ch.title or "Refactor", ch.language, ch.complexity),
    ch.description or "",
    "Find the bug(s), improve naming/structure, keep behaviour. Use motions, not arrows.",
  }
  vim.cmd("aboveleft 4split")
  s.info_win = vim.api.nvim_get_current_win()
  s.info_buf = scratch(lines)
  vim.api.nvim_win_set_buf(s.info_win, s.info_buf)
  vim.wo[s.info_win].wrap = true
  vim.wo[s.info_win].winfixheight = true
  vim.wo[s.info_win].number = false
  vim.wo[s.info_win].relativenumber = false
  vim.wo[s.info_win].signcolumn = "no"
end

local function close_ui()
  local s = M.current
  if not s then
    return
  end
  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end
  for _, w in ipairs({ s.bar_win, s.info_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  vim.on_key(nil, NS)
  vim.api.nvim_clear_autocmds({ group = AUGROUP })
end

-- ── state transitions ───────────────────────────────────────────────────────
local function set_modifiable(v)
  local s = M.current
  if s and vim.api.nvim_buf_is_valid(s.buf) then
    vim.bo[s.buf].modifiable = v
  end
end

function M.open(ch)
  if M.current then
    vim.notify("LearnRefactor: a session is active - :RefactorStop first", vim.log.levels.WARN)
    return
  end
  local lang = config.options.languages[ch.language] or {}
  local ext = lang.ext or ch.language
  local file = store.workspace(ch.id) .. "/main." .. ext
  vim.fn.writefile(vim.split(ch.code, "\n", { plain = true }), file)

  vim.cmd("tabnew " .. vim.fn.fnameescape(file))
  local s = {
    ch = ch,
    state = "ready",
    file = file,
    buf = vim.api.nvim_get_current_buf(),
    win = vim.api.nvim_get_current_win(),
    tab = vim.api.nvim_get_current_tabpage(),
    elapsed_ns = 0,
    metrics = { keys = 0, arrows = 0, mouse = 0, spam = 0, hints = 0 },
    streak = 0,
    hint_idx = 0,
    keylog = {},
  }
  M.current = s
  vim.bo[s.buf].modifiable = false
  open_info()
  refocus()
  if config.options.control_bar then
    open_bar()
  end
  vim.on_key(on_key, NS)

  s.timer = vim.uv.new_timer()
  s.timer:start(1000, 1000, vim.schedule_wrap(function()
    render_bar()
    vim.cmd("redrawstatus")
  end))

  -- closing the challenge buffer aborts the session
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = AUGROUP,
    buffer = s.buf,
    callback = function()
      vim.schedule(function()
        if M.current and M.current.buf == s.buf then
          M.stop(true)
        end
      end)
    end,
  })
  emit("Open", { id = ch.id })
  -- `keymaps` may be false (lazy.nvim `keys` owns the mappings)
  local play_key = (config.options.keymaps or {}).play
  vim.notify("Refactor ready - :RefactorPlay" .. (play_key and (" or " .. play_key) or "") .. " starts the clock")
end

function M.play()
  local s = M.current
  if not s or s.state == "running" then
    return
  end
  s.state = "running"
  s.started_ns = now()
  set_modifiable(true)
  refocus()
  emit("Play", { id = s.ch.id })
end

function M.pause()
  local s = M.current
  if not s or s.state ~= "running" then
    return
  end
  s.elapsed_ns = s.elapsed_ns + (now() - s.started_ns)
  s.state = "paused"
  set_modifiable(false)
  emit("Pause", { id = s.ch.id })
  vim.notify("Paused at " .. fmt_time(M.elapsed()))
end

function M.hint()
  local s = M.current
  if not s or s.state ~= "running" then
    return
  end
  local bugs = s.ch.bugs or {}
  if s.hint_idx >= #bugs then
    vim.notify("No more hints", vim.log.levels.INFO)
    return
  end
  s.hint_idx = s.hint_idx + 1
  s.metrics.hints = s.metrics.hints + 1
  vim.notify(string.format("Hint %d (-%d pts): %s", s.hint_idx, config.options.hint_cost,
    bugs[s.hint_idx].hint or "Re-read the control flow."))
end

function M.stop(silent)
  local s = M.current
  if not s then
    return
  end
  close_ui()
  M.current = nil
  if vim.api.nvim_buf_is_valid(s.buf) then
    vim.bo[s.buf].modifiable = true
  end
  store.append_history({
    challenge_id = s.ch.id, language = s.ch.language, complexity = s.ch.complexity,
    status = "stopped", seconds = math.floor(M.elapsed_of(s)), at = os.time(),
  })
  emit("Stop", { id = s.ch.id })
  if not silent then
    vim.notify("Refactor stopped (no score)")
  end
end

function M.elapsed_of(s)
  return (s.elapsed_ns + (s.state == "running" and (now() - s.started_ns) or 0)) / 1e9
end

local function show_result(s, result)
  local lines = { string.format(" %s  [%s/%s]", s.ch.title, s.ch.language, s.ch.complexity), "" }
  if result.note then
    lines[#lines + 1] = " " .. result.note
  end
  for _, l in ipairs(result.lines) do
    lines[#lines + 1] = string.format(" %s %-52s %+4d", l.ok and "✔" or "✘", l.label, l.points)
  end
  if result.tests_ok == false and result.test_output and result.test_output:match("%S") then
    lines[#lines + 1] = ""
    lines[#lines + 1] = " Test output:"
    local shown = 0
    for l in result.test_output:gmatch("[^\n]+") do
      shown = shown + 1
      if shown > 6 then
        break
      end
      lines[#lines + 1] = "   " .. l
    end
  end
  if result.points > 0 or result.max_points > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(" TOTAL %d / %d   time %s   keys %d", result.points, result.max_points,
      fmt_time(result.seconds), s.metrics.keys)
  end
  if result.coach and #result.coach > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = " Motion coach:"
    for _, t in ipairs(result.coach) do
      lines[#lines + 1] = "  - " .. t
    end
  end
  if result.advice and #result.advice > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = " Your setup:"
    for _, t in ipairs(result.advice) do
      lines[#lines + 1] = "  " .. t
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = s.ch.solution and " q close   s reference solution" or " q close"

  local b = scratch(lines)
  local width = math.min(100, vim.o.columns - 6)
  local height = 0
  for _, l in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / (width - 1)))
  end
  height = math.min(height, vim.o.lines - 6)
  local w = vim.api.nvim_open_win(b, true, {
    relative = "editor", style = "minimal", border = "rounded", title = " Result ",
    width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  vim.wo[w].wrap = true
  vim.wo[w].linebreak = true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, w, true)
    end, { buffer = b, nowait = true })
  end
  if s.ch.solution then
    vim.keymap.set("n", "s", function()
      pcall(vim.api.nvim_win_close, w, true)
      local ext = (config.options.languages[s.ch.language] or {}).ext or s.ch.language
      local sb = scratch(vim.split(s.ch.solution, "\n", { plain = true }))
      vim.bo[sb].filetype = vim.filetype.match({ filename = "main." .. ext }) or ""
      vim.cmd("tabnew")
      vim.api.nvim_win_set_buf(0, sb)
    end, { buffer = b, nowait = true })
  end
end

function M.finish()
  local s = M.current
  if not s then
    return
  end
  if s.state == "ready" then
    vim.notify("Press Play first", vim.log.levels.WARN)
    return
  end
  if s.state == "running" then
    s.elapsed_ns = s.elapsed_ns + (now() - s.started_ns)
  end
  s.state = "finished"
  set_modifiable(true)
  local text = table.concat(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  if text:sub(-1) ~= "\n" and s.ch.code:sub(-1) == "\n" then
    text = text .. "\n"
  end
  vim.api.nvim_buf_call(s.buf, function()
    vim.cmd("silent! write")
  end)

  local errors
  local lsp = #vim.lsp.get_clients({ bufnr = s.buf }) > 0
  if lsp then
    errors = #vim.diagnostic.get(s.buf, { severity = vim.diagnostic.severity.ERROR })
  end
  local m = vim.tbl_extend("force", s.metrics, { seconds = s.elapsed_ns / 1e9, errors = errors })

  local coach_tips, coach_stats = require("learn_refactor.coach").analyze(s.keylog, m)
  store.add_habits(vim.tbl_extend("force", coach_stats, { arrows = m.arrows, mouse = m.mouse }))
  local advice = require("learn_refactor.advisor").lines({ stats = coach_stats, metrics = m, lsp = lsp }, 5)

  close_ui()
  M.current = nil
  scoring.score(s.ch, text, m, function(result)
    result.seconds = m.seconds
    result.coach = coach_tips
    result.advice = advice
    scoring.update_profile(s.ch, result)
    store.append_history({
      challenge_id = s.ch.id, language = s.ch.language, complexity = s.ch.complexity,
      status = "finished", points = result.points, max_points = result.max_points,
      seconds = math.floor(m.seconds), keys = m.keys, arrows = m.arrows, mouse = m.mouse,
      spam = m.spam, hints = m.hints, at = os.time(),
    })
    emit("Finish", { id = s.ch.id, points = result.points })
    show_result(s, result)
  end)
end

return M

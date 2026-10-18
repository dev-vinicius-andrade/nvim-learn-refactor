-- Inspects the user's own Neovim setup (options, plugins, mappings) and suggests improvements.
-- Never changes anything: it only reports.
local M = {}

--- names of installed plugins, lowercased (lazy.nvim registry, else runtimepath dirs)
local function plugin_names()
  local names = {}
  local ok, lazy_config = pcall(require, "lazy.core.config")
  if ok and type(lazy_config.plugins) == "table" then
    for k, p in pairs(lazy_config.plugins) do
      names[#names + 1] = (type(p) == "table" and p.name or tostring(k)):lower()
    end
  end
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    names[#names + 1] = vim.fs.basename(path):lower()
  end
  return names
end

local function has_any(names, needles)
  for _, n in ipairs(names) do
    for _, needle in ipairs(needles) do
      if n:find(needle, 1, true) then
        return true
      end
    end
  end
  return false
end

--- ctx (optional): { stats = coach stats, metrics = session metrics, lsp = bool }
--- returns list of { tip = string, topic = string, relevant = bool }
function M.analyze(ctx)
  ctx = ctx or {}
  local stats = ctx.stats or {}
  local metrics = ctx.metrics or {}
  local names = plugin_names()
  local out = {}
  local function add(topic, tip, relevant)
    out[#out + 1] = { topic = topic, tip = tip, relevant = relevant or false, order = #out }
  end

  local moved_a_lot = (stats.vertical or 0) + (stats.horizontal or 0) + (stats.words or 0) > 0
  local o = vim.o

  -- options
  if not o.relativenumber then
    add("options", "`:set relativenumber` shows distance in every line, so `7j` / `12k` are one glance away.", moved_a_lot)
  end
  if o.scrolloff < 5 then
    add("options", "`:set scrolloff=8` keeps context visible around the cursor when you jump.")
  end
  if not (o.ignorecase and o.smartcase) then
    add("options", "`:set ignorecase smartcase` makes `/` and `*` searches case-insensitive unless you type capitals.")
  end
  if o.inccommand == "" then
    add("options", "`:set inccommand=split` previews `:s/old/new/` live, great for safe renames.")
  end
  if not o.undofile then
    add("options", "`:set undofile` keeps undo history across sessions so you can experiment fearlessly.")
  end
  if o.timeoutlen > 800 then
    add("options", "`timeoutlen` is " .. o.timeoutlen .. "ms; 300-500 makes multi-key mappings feel snappier.")
  end
  if o.mouse ~= "" and (metrics.mouse or 0) > 0 then
    add("options", "Mouse is enabled and you clicked. While practicing, `:set mouse=` removes the temptation.", true)
  end

  -- jumping around
  if not has_any(names, { "flash", "leap", "hop", "sneak" }) then
    add("plugins", "A jump plugin (flash.nvim, leap.nvim, hop.nvim) reaches any visible spot in 2-3 keys, replacing long `hjkl`/`w` runs.", moved_a_lot)
  end
  if not has_any(names, { "surround" }) then
    add("plugins", "nvim-surround / mini.surround adds `ysiw\"`, `cs\"'`, `ds(`: wrap, change and delete delimiters in 3 keys.")
  end
  if not has_any(names, { "mini.ai", "textobjects", "various-textobjs" }) then
    add("plugins", "mini.ai or nvim-treesitter-textobjects adds `af`/`if` (function), `ac` (class), `aa` (argument) text objects.")
  end
  if not has_any(names, { "which-key" }) then
    add("plugins", "which-key.nvim shows available keys after a prefix, handy for discovering motions and your own mappings.")
  end
  if not has_any(names, { "telescope", "fzf-lua", "snacks", "mini.pick" }) then
    add("plugins", "A fuzzy finder (telescope, fzf-lua, snacks.picker) finds files and symbols without manual navigation.")
  end
  if not has_any(names, { "conform", "none-ls", "null-ls", "guard", "formatter" }) then
    add("plugins", "A formatter integration (conform.nvim) removes formatting busywork, so refactors stay about structure.")
  end
  if not has_any(names, { "treesitter" }) then
    add("plugins", "nvim-treesitter gives better highlighting, folding and structural text objects.")
  end

  -- LSP refactoring tools
  if vim.fn.has("nvim-0.11") == 1 then
    if ctx.lsp then
      add("lsp", "LSP is attached: `grn` renames a symbol, `gra` opens code actions (extract, inline, fix), `grr` lists references.", true)
    end
  else
    local missing = {}
    for _, key in ipairs({ "gd", "gr", "K" }) do
      if vim.fn.maparg(key, "n") == "" then
        missing[#missing + 1] = "`" .. key .. "`"
      end
    end
    if #missing > 0 then
      add("lsp", "No normal-mode mapping for " .. table.concat(missing, ", ")
        .. ". Map them to vim.lsp.buf.definition / references / hover (rename and code_action too) for fast refactors.", ctx.lsp)
    end
  end
  if ctx.lsp == false then
    add("lsp", "No LSP client attached to the exercise buffer: set one up for this language to get rename, diagnostics and code actions while refactoring.", true)
  end

  -- relevant (tied to this session) first, then the rest; stable within each group
  table.sort(out, function(a, b)
    if a.relevant ~= b.relevant then
      return a.relevant
    end
    return a.order < b.order
  end)
  return out
end

--- formatted lines for display; limit caps the count
function M.lines(ctx, limit)
  local lines = {}
  for i, t in ipairs(M.analyze(ctx)) do
    if i > (limit or 6) then
      break
    end
    lines[#lines + 1] = "- " .. t.tip
  end
  if #lines == 0 then
    lines[1] = "- Your setup already covers the basics. Nice."
  end
  return lines
end

return M

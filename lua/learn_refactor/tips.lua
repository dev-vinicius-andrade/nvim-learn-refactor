-- Short Neovim tips shown in the menu. Habit-specific tips are picked from what the motion coach
-- has seen the user do; otherwise a general tip rotates by day.
local M = {}

M.by_habit = {
  vertical = {
    "Jump by paragraph with } and {, by half page with <C-d> / <C-u>.",
    "Use a count: 12j moves 12 lines. Turn on relativenumber to read the distance.",
    "/text<CR> then n/N beats holding j. Use gg, G, or :42<CR> for absolute jumps.",
  },
  horizontal = {
    "f{char} jumps to the next {char} on the line, ; repeats it, , reverses it.",
    "0 / ^ / $ go to line start / first word / line end. w e b move by word.",
    "t{char} stops just before {char}: dt) deletes up to the closing paren.",
  },
  words = {
    "Use e/ge to land on word ends, W/B/E to skip punctuation as one WORD.",
    "Search with /pattern when the target is more than 3 words away.",
  },
  xs = {
    "x x x x ... : use dw (word), daw (word + space), D (to end of line), dd (line).",
  },
  bs = {
    "In insert mode <C-w> deletes a word and <C-u> the line. Or leave insert and use ciw.",
    "ciw changes the word under the cursor from anywhere inside it; . repeats it elsewhere.",
  },
  arrows = {
    "Arrow keys leave the home row. hjkl, w/b, f/t and / are always faster once learned.",
  },
  mouse = {
    "Instead of clicking: / to search, * for the word under cursor, ma then 'a to mark and return.",
  },
}

M.general = {
  "ciw / caw / ci( / ci\" change inside or around text objects, from anywhere within them.",
  "The dot command . repeats your last change: make one good edit, then jump and press .",
  "* searches for the word under the cursor; n / N cycle through the matches.",
  "% jumps between matching brackets; v% selects the whole block.",
  "Record a macro with qa ... q and replay it with @a, then @@. Prefix a count: 20@a.",
  ":%s/old/new/gc replaces with confirmation. Add \\< \\> around old to match whole words.",
  "gv reselects the last visual selection. o jumps to the other end of it.",
  "<C-o> and <C-i> walk back and forward through your jump list.",
  "`` jumps back to where you were before the last jump. ma / 'a set and use marks.",
  "gi returns to the last place you inserted text and enters insert mode.",
  "A appends at end of line, I inserts at first non-blank, o / O open a line below / above.",
  "u undoes, <C-r> redoes, g- and g+ travel back and forth in the undo tree in time.",
  "zz / zt / zb scroll the current line to the middle / top / bottom of the window.",
  ":g/pattern/d deletes every matching line; :v/pattern/d deletes every non-matching one.",
  "yiw then viwp replaces a word with the yanked one; \"_d deletes without touching registers.",
  "Visual block: <C-v>, select a column, I or A to insert on every line, <Esc> to apply.",
  "gcc comments a line, gc{motion} a range (built in since Neovim 0.10).",
  "grn renames, gra opens code actions, grr lists references (built-in LSP maps in 0.11+).",
}

--- profile.habits = cumulative counters from finished sessions
function M.pick(habits)
  local best, best_n = nil, 0
  for habit, n in pairs(habits or {}) do
    if M.by_habit[habit] and n > best_n then
      best, best_n = habit, n
    end
  end
  if best then
    local list = M.by_habit[best]
    return list[(os.time() % #list) + 1], best
  end
  local day = math.floor(os.time() / 86400)
  return M.general[(day % #M.general) + 1]
end

return M

-- Turns the recorded key log into concrete "do this instead" tips.
local M = {}

local OPERATOR_PENDING_OR_VISUAL = { no = true, nov = true, noV = true, ["no\22"] = true, v = true, V = true, ["\22"] = true }

local function plural(n)
  return n == 1 and "" or "s"
end

--- log: list of { key, mode } in typed order; metrics: session metrics
--- returns list of tip strings
function M.analyze(log, metrics)
  local tips = {}
  local hjkl, word, xs, bs = {}, {}, 0, 0

  local i, n = 1, #log
  while i <= n do
    local e = log[i]
    local j = i
    while j < n and log[j + 1][1] == e[1] and log[j + 1][2] == e[2] do
      j = j + 1
    end
    local run = j - i + 1
    local key, mode = e[1], e[2]
    if mode == "n" then
      if key:match("^[hjkl]$") and run >= 5 then
        hjkl[key] = (hjkl[key] or 0) + run
      elseif key:match("^[wbWB]$") and run >= 4 then
        word[key] = (word[key] or 0) + run
      elseif key == "x" and run >= 4 then
        xs = xs + run
      end
    elseif mode == "i" and key == "<BS>" and run >= 6 then
      bs = bs + run
    end
    i = j + 1
  end

  local vertical = (hjkl.j or 0) + (hjkl.k or 0)
  if vertical > 0 then
    tips[#tips + 1] = string.format(
      "%d j/k presses in long runs: use a count (`12j`), `}`/`{`, `<C-d>`/`<C-u>`, `/pattern`, `gg`/`G` or `:{line}`.", vertical)
  end
  local horizontal = (hjkl.h or 0) + (hjkl.l or 0)
  if horizontal > 0 then
    tips[#tips + 1] = string.format(
      "%d h/l presses in long runs: use `f{char}`/`t{char}`, `w`/`e`/`b`, `0`/`^`/`$`.", horizontal)
  end
  local words = 0
  for _, c in pairs(word) do
    words = words + c
  end
  if words > 0 then
    tips[#tips + 1] = string.format(
      "%d w/b word-steps in a row: jump with `f{char}`, `e`/`ge`, `W`/`B` for WORDS, or search with `/`.", words)
  end
  if xs > 0 then
    tips[#tips + 1] = string.format("%d `x` in a row: use `dw`, `daw`, `D` or `d$`.", xs)
  end
  if bs > 0 then
    tips[#tips + 1] = string.format(
      "%d backspaces in a row: use `<C-w>` (delete word), `<C-u>`, or fix it from normal mode with `ciw`/`cw`.", bs)
  end
  if (metrics.arrows or 0) > 0 then
    tips[#tips + 1] = string.format(
      "%d arrow key%s used: stay on the home row, `hjkl` with counts or word/search motions are faster.",
      metrics.arrows, plural(metrics.arrows))
  end
  if (metrics.mouse or 0) > 0 then
    tips[#tips + 1] = string.format("%d mouse click%s: try `/pattern`, `*`, `%%`, marks (`ma` / `'a`).",
      metrics.mouse, plural(metrics.mouse))
  end

  -- features never used (only judge on a long enough session)
  if n >= 40 then
    local used = {}
    for k = 1, n do
      local key, mode = log[k][1], log[k][2]
      if (key == "i" or key == "a") and OPERATOR_PENDING_OR_VISUAL[mode] then
        used.textobj = true
      elseif mode == "n" then
        if key == "." then used.dot = true
        elseif key == "*" or key == "#" then used.star = true
        elseif key == "%" then used.percent = true
        elseif key == "q" or key == "@" then used.macro = true
        end
      end
    end
    local missing = {}
    local function want(flag, text)
      if not used[flag] and #missing < 3 then
        missing[#missing + 1] = text
      end
    end
    want("textobj", "text objects (`ciw`, `di(`, `yap`, `vit`)")
    want("dot", "the dot command `.` to repeat the last change")
    want("star", "`*` / `#` to jump between uses of the word under cursor")
    want("percent", "`%` to jump between matching brackets")
    want("macro", "macros (`qa ... q`, `@a`, `@@`) for repeated edits")
    if #missing > 0 then
      tips[#tips + 1] = "Not used this time, try: " .. table.concat(missing, "; ") .. "."
    end
  end

  if #tips == 0 then
    tips[#tips + 1] = "No bad habits spotted. Nice motions."
  end
  return tips, { vertical = vertical, horizontal = horizontal, words = words, xs = xs, bs = bs }
end

return M

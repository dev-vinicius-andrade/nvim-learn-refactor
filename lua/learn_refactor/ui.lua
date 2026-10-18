-- Uses vim.ui.select, so telescope-ui-select / snacks / dressing / fzf-lua etc. take over automatically.
local config = require("learn_refactor.config")
local store = require("learn_refactor.store")
local generator = require("learn_refactor.generator")
local session = require("learn_refactor.session")

local M = {}

local function sorted_languages()
  local names = vim.tbl_keys(config.options.languages)
  table.sort(names)
  return names
end

local function start(ch, err)
  if not ch then
    return vim.notify("LearnRefactor: " .. tostring(err), vim.log.levels.ERROR)
  end
  session.open(ch)
end

--- set of enabled language names
local function enabled()
  local set = {}
  for name in pairs(config.options.languages) do
    set[name] = true
  end
  return set
end

--- unfinished challenges in the languages the user enabled (latest first)
function M.unfinished()
  return store.unfinished(enabled())
end

--- jump straight to the latest unfinished challenge, keeping previous edits and clock
function M.continue()
  local list = M.unfinished()
  if #list == 0 then
    return vim.notify("LearnRefactor: nothing unfinished - start a new challenge with :Refactor", vim.log.levels.INFO)
  end
  session.open(list[1].ch, { resume = true, seconds = list[1].seconds })
end

function M.generate(language, complexity)
  vim.notify(string.format("LearnRefactor: generating %s / %s ...", language, complexity))
  generator.generate(language, complexity, start)
end

function M.library(language, complexity)
  local list = store.list_challenges({ language = language, complexity = complexity })
  if #list == 0 then
    return vim.notify("LearnRefactor: library is empty for that selection", vim.log.levels.INFO)
  end
  local pending = {}
  for _, u in ipairs(M.unfinished()) do
    pending[u.ch.id] = u
  end
  vim.ui.select(list, {
    prompt = "Saved challenges",
    format_item = function(c)
      return string.format("%s  [%s/%s]  %s%s", c.title, c.language, c.complexity,
        os.date("%Y-%m-%d", c.created_at or 0), pending[c.id] and "  (unfinished)" or "")
    end,
  }, function(choice)
    if not choice then
      return
    end
    local u = pending[choice.id]
    if u and u.seconds then
      return session.open(choice, { resume = true, seconds = u.seconds })
    end
    start(choice)
  end)
end

--- Interactive flow: language -> complexity -> new | library
function M.menu(opts)
  opts = opts or {}
  local function with_language(lang)
    vim.ui.select(config.options.complexities, { prompt = "Complexity" }, function(cx)
      if not cx then
        return
      end
      if opts.library then
        return M.library(lang, cx)
      end
      vim.ui.select({ "Generate new", "From library" }, { prompt = "Source" }, function(src)
        if src == "Generate new" then
          M.generate(lang, cx)
        elseif src == "From library" then
          M.library(lang, cx)
        end
      end)
    end)
  end
  if opts.language then
    return with_language(opts.language)
  end
  vim.ui.select(sorted_languages(), { prompt = "Language" }, function(lang)
    if lang then
      with_language(lang)
    end
  end)
end

--- standalone review of the user's own Neovim setup
function M.config_tips()
  local lines = require("learn_refactor.advisor").lines({}, 20)
  vim.notify("Setup tips:\n" .. table.concat(lines, "\n"))
end

function M.stats()
  local p = store.profile()
  local lines = { "Total points: " .. (p.total_points or 0), "" }
  local tags = {}
  for tag, s in pairs(p.tags or {}) do
    tags[#tags + 1] = { tag = tag, rate = s.passed / math.max(1, s.seen), seen = s.seen }
  end
  table.sort(tags, function(a, b)
    return a.rate < b.rate
  end)
  lines[#lines + 1] = "Skill by topic (weakest first):"
  for _, t in ipairs(tags) do
    lines[#lines + 1] = string.format("  %-18s %3d%%  (%d)", t.tag, math.floor(t.rate * 100), t.seen)
  end
  vim.notify(table.concat(lines, "\n"))
end

return M

-- Builds adaptive prompts from the user's history and asks a provider for a challenge.
local config = require("learn_refactor.config")
local store = require("learn_refactor.store")

local M = {}

local GUIDE = {
  easy = "30-50 lines, 1 bug, 3-4 code smells",
  medium = "60-100 lines, 2 bugs, 5-6 code smells, a couple of functions interacting",
  hard = "100-160 lines, 3 subtle bugs, 6-8 smells, mixed responsibilities, hidden coupling",
  expert = "160-250 lines, 4 subtle bugs (concurrency/edge cases/off-by-one/resource leaks), 8+ smells, tangled design",
}

--- Summarize what the user struggled with so far -> steers the next generation.
function M.adaptive_hints(language)
  local profile = store.profile()
  local weak, strong = {}, {}
  for tag, s in pairs(profile.tags or {}) do
    if s.seen >= 2 then
      local rate = s.passed / s.seen
      if rate < 0.5 then
        weak[#weak + 1] = tag
      elseif rate > 0.85 then
        strong[#strong + 1] = tag
      end
    end
  end
  table.sort(weak)
  table.sort(strong)

  local recent = {}
  local past = store.list_challenges({ language = language })
  for i = 1, math.min(#past, 12) do
    recent[#recent + 1] = past[i].title
  end

  local hist = store.history()
  local last = {}
  for i = math.max(1, #hist - 4), #hist do
    local h = hist[i]
    if h and h.language == language then
      last[#last + 1] = string.format("%s: %d/%d", h.complexity, h.points or 0, h.max_points or 0)
    end
  end
  return { weak = weak, strong = strong, recent_titles = recent, last_results = last }
end

local SCHEMA = [[
Respond with ONE JSON object only (no markdown fences, no prose) with this shape:
{
  "title": "short unique title",
  "description": "1-2 sentences describing what the code is supposed to do (do NOT reveal bugs)",
  "code": "full source file as a string",
  "bugs": [ { "id": "kebab-id", "points": 30, "hint": "vague nudge", "description": "what is wrong",
              "fixed": { "type": "absent"|"present", "pattern": "vim very-magic regex" } } ],
  "standards": [ { "id": "kebab-id", "tag": "naming|duplication|magic-numbers|error-handling|idioms|stdlib|scoping|functional|complexity|types|...",
                   "name": "human readable rule", "points": 10,
                   "check": { "type": "absent"|"present", "pattern": "vim very-magic regex" } } ],
  "run_cmd": "optional shell command using {file}; exit code 0 means behaviour is correct after fixes (omit if not feasible)"
}
Rules for checks: patterns are Vim regex in very-magic mode (\v), case-sensitive, matched against the WHOLE file text
(use \n for newlines). In very-magic mode ESCAPE literal = ~ @ % & { } with a backslash (e.g. \= for a literal equals sign) and use <word> for word boundaries (there is no \b). A "bug" check must be FALSE on the original code and TRUE once any reasonable fix is applied;
prefer "absent" checks of the buggy construct. Same for standards: the check must fail on the original code.
Make patterns tolerant of different valid refactorings (do not require one exact variable name).
The code MUST be idiomatic-looking but flawed, and must compile/run before refactoring.]]

function M.build_prompt(language, complexity)
  local h = M.adaptive_hints(language)
  local lines = {
    string.format("Create a code-refactoring exercise in %s. Difficulty: %s (%s).", language, complexity, GUIDE[complexity] or ""),
    "The learner practices Neovim terminal skills; they will edit the file with vim motions.",
    "Bake in real-world bugs and code smells, not toy puzzles.",
  }
  if #h.weak > 0 then
    lines[#lines + 1] = "Learner struggles with: " .. table.concat(h.weak, ", ") .. ". Emphasize these."
  end
  if #h.strong > 0 then
    lines[#lines + 1] = "Learner is already strong at: " .. table.concat(h.strong, ", ") .. ". Do not focus on these."
  end
  if #h.last_results > 0 then
    lines[#lines + 1] = "Recent results in this language (complexity: points/max): " .. table.concat(h.last_results, "; ") .. ". Calibrate difficulty within the requested level."
  end
  if #h.recent_titles > 0 then
    lines[#lines + 1] = "Already used, DO NOT repeat these themes: " .. table.concat(h.recent_titles, "; ") .. "."
  end
  lines[#lines + 1] = SCHEMA
  return table.concat(lines, "\n")
end

local function strip_fences(s)
  s = s:gsub("^%s*```%w*%s*\n", ""):gsub("\n```%s*$", "")
  return s
end

function M.parse(raw)
  local ok, data = pcall(vim.json.decode, strip_fences(raw))
  if not ok or type(data) ~= "table" then
    -- try to grab the outermost {...}
    local body = raw:match("%b{}")
    ok, data = pcall(vim.json.decode, body or "")
  end
  if not ok or type(data) ~= "table" or type(data.code) ~= "string" or type(data.title) ~= "string" then
    return nil, "provider returned invalid challenge JSON"
  end
  data.bugs = data.bugs or {}
  data.standards = data.standards or {}
  return data
end

local function validate_checks(ch)
  -- the original code must FAIL every check, otherwise it awards free points
  local scoring = require("learn_refactor.scoring")
  local dropped = 0
  local function keep(list, get)
    local out = {}
    for _, item in ipairs(list) do
      local res = scoring.run_check(get(item), ch.code)
      if res == false then
        out[#out + 1] = item
      else
        dropped = dropped + 1
      end
    end
    return out
  end
  ch.bugs = keep(ch.bugs, function(b) return b.fixed end)
  ch.standards = keep(ch.standards, function(s) return s.check end)
  return dropped
end

--- Generate async. cb(challenge|nil, err|nil)
function M.generate(language, complexity, cb)
  local opts = config.options
  local function finish(ch, err)
    if ch then
      ch.language, ch.complexity = language, complexity
      validate_checks(ch)
      if #ch.bugs == 0 and #ch.standards == 0 then
        return cb(nil, "challenge had no usable checks")
      end
      local _, saved = store.save_challenge(ch)
      return cb(saved)
    end
    if opts.fallback then
      local ch2 = M.fallback(language, complexity)
      if ch2 then
        vim.notify("LearnRefactor: " .. tostring(err) .. " - using saved/built-in challenge", vim.log.levels.WARN)
        return cb(ch2)
      end
    end
    cb(nil, err)
  end

  local route = (opts.routes or {})[complexity] or {}
  local name = route.provider or opts.provider
  if name == "static" then
    return finish(nil, "static provider")
  end
  local found, provider = pcall(require, "learn_refactor.provider." .. name)
  if not found then
    return finish(nil, "unknown provider: " .. tostring(name))
  end
  provider.request(M.build_prompt(language, complexity), function(raw, err)
    if not raw then
      return finish(nil, err)
    end
    local ch, perr = M.parse(raw)
    finish(ch, perr)
  end, route)
end

--- Pick an unseen saved challenge, then built-in seeds.
function M.fallback(language, complexity)
  local done = {}
  for _, h in ipairs(store.history()) do
    done[h.challenge_id] = true
  end
  local pool = store.list_challenges({ language = language, complexity = complexity })
  for _, ch in ipairs(pool) do
    if not done[ch.id] then
      return ch
    end
  end
  local seeds = vim.tbl_filter(function(s)
    return s.language == language
  end, require("learn_refactor.seeds"))
  if #seeds == 0 then
    return pool[1]
  end
  local seed = vim.deepcopy(seeds[math.random(#seeds)])
  local _, saved = store.save_challenge(seed)
  return saved
end

return M

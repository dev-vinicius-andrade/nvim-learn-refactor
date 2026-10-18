-- Built-in offline challenges. Check patterns are Vim very-magic regex (case-sensitive),
-- matched against the whole buffer text.
return {
  {
    title = "Order totals",
    language = "lua",
    complexity = "easy",
    description = "Order totals calculator. Make it clean, idiomatic and correct.",
    code = [[
function calc(o)
  local t = 0
  for i = 0, #o do
    t = t + o[i].price * o[i].qty
  end
  if t > 100 then
    t = t - t * 10 / 100
  end
  if t > 100 then
    return t
  else
    return t
  end
end
]],
    bugs = {
      {
        id = "off-by-one",
        points = 30,
        hint = "Look at the loop bounds.",
        description = "Loop starts at 0 but Lua arrays start at 1",
        fixed = { type = "absent", pattern = "for i \\= 0," },
      },
    },
    standards = {
      { id = "local-fn", tag = "scoping", name = "Function is local/module scoped", points = 10,
        check = { type = "present", pattern = "local function|local M" } },
      { id = "named", tag = "naming", name = "Descriptive function name", points = 10,
        check = { type = "absent", pattern = "function calc\\(" } },
      { id = "dup-branch", tag = "duplication", name = "Duplicate if/else branches removed", points = 10,
        check = { type = "absent", pattern = "return t\\n\\s*else\\n\\s*return t" } },
      { id = "magic", tag = "magic-numbers", name = "Magic numbers named", points = 10,
        check = { type = "present", pattern = "^\\s*(local\\s+)?[A-Z][A-Z_0-9]+\\s*\\=" } },
    },
  },
  {
    title = "Word counter",
    language = "python",
    complexity = "easy",
    description = "Counts words in text. Refactor to idiomatic Python and fix the bug.",
    code = [[
def f(s):
    d = {}
    words = s.split(" ")
    for i in range(len(words)):
        w = words[i]
        if w in d.keys():
            d[w] = d[w] + 1
        else:
            d[w] = 1
    return d
]],
    bugs = {
      {
        id = "split-space",
        points = 30,
        hint = "What happens with multiple spaces or newlines?",
        description = "split(' ') yields empty strings for repeated whitespace",
        fixed = { type = "absent", pattern = "split\\(\" \"\\)|split\\(' '\\)" },
      },
    },
    standards = {
      { id = "counter", tag = "stdlib", name = "Use collections.Counter or defaultdict", points = 15,
        check = { type = "present", pattern = "Counter|defaultdict" } },
      { id = "no-range-len", tag = "idioms", name = "No range(len(...)) loop", points = 10,
        check = { type = "absent", pattern = "range\\(len\\(" } },
      { id = "name", tag = "naming", name = "Descriptive function name", points = 10,
        check = { type = "absent", pattern = "def f\\(" } },
    },
  },
  {
    title = "User filter",
    language = "javascript",
    complexity = "medium",
    description = "Filters active adult users. Modernize it and find the bug.",
    code = [[
function getUsers(users) {
  var result = [];
  for (var i = 0; i <= users.length; i++) {
    if (users[i].active == true && users[i].age >= 18) {
      result.push(users[i].name.toUpperCase());
    }
  }
  return result;
}
]],
    bugs = {
      {
        id = "oob",
        points = 30,
        hint = "Check the loop condition against the array length.",
        description = "<= users.length reads past the end",
        fixed = { type = "absent", pattern = "<= users\\.length" },
      },
    },
    standards = {
      { id = "no-var", tag = "modern-syntax", name = "No var", points = 10,
        check = { type = "absent", pattern = "<var>" } },
      { id = "strict-eq", tag = "equality", name = "No loose ==", points = 10,
        check = { type = "absent", pattern = "[^=!]\\=\\=[^=]" } },
      { id = "hof", tag = "functional", name = "filter/map instead of manual loop", points = 15,
        check = { type = "present", pattern = "\\.filter\\(|\\.map\\(|for \\(const .* of" } },
    },
  },
}

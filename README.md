# nvim-learn-refactor

Practice refactoring (and Neovim motions) on generated code. Pick a language and complexity, get a flawed
program, hit **Play**, fix bugs and smells, hit **Finish** and get scored.

Requires Neovim 0.10+. Works with whatever you already have: the exercise is a real file
(`<data>/learn-refactor/workspace/<id>/main.<ext>`), so LSP, treesitter, formatters, completion and linters attach normally.
Pickers use `vim.ui.select` (telescope-ui-select, snacks, dressing, fzf-lua... take over automatically).

## Install (lazy.nvim)

```lua
{
  "dev-vinicius-andrade/nvim-learn-refactor",
  cmd = { "Refactor", "RefactorLibrary", "RefactorStats" },
  opts = {},               -- see lua/learn_refactor/config.lua
}
```

Challenge generation uses the Anthropic API via `curl`: `export ANTHROPIC_API_KEY=...`.
Without a key (or on failure) it falls back to your saved library, then built-in seeds. Run `:checkhealth learn-refactor`.

## Usage

| Command | Action |
|---|---|
| `:Refactor [lang] [complexity] [library]` | menu, or direct start |
| `:RefactorPlay` / `Pause` / `Stop` / `Finish` | session control (also clickable bar, top-right) |
| `:RefactorHint` | reveal next bug hint (-5 pts) |
| `:RefactorLibrary` | replay a saved challenge |
| `:RefactorStats` | points + weakest topics |

Default keymaps: `<leader>rp` play, `rP` pause, `rs` stop, `rf` finish, `rh` hint (`keymaps = false`-ish: set entries to `false`).

Statusline: `require("learn_refactor").statusline()`. Events: `User LearnRefactorOpen|Play|Pause|Stop|Finish`.

## Scoring

- Bugs found/fixed (check per bug), best-practice rules (naming, duplication, magic numbers, idioms...)
- Optional `run_cmd` behaviour check (+40), no LSP errors (+10), speed bonus vs par time (+15)
- Clean motions bonus (+10); penalty per arrow key, mouse click, or `hjkl` repeated >4x (max -15); hints cost points

## Adaptive generation

Every saved challenge goes to `challenges/*.json`. Results update `profile.json` (pass rate per topic) and
`history.json`. The next prompt tells the model your weak/strong topics, recent results, and titles to avoid repeating.

Storage is plain JSON files in `stdpath("data")/learn-refactor` (`data_dir` option).

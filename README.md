# nvim-learn-refactor

Practice refactoring (and Neovim motions) on generated code. Pick a language and complexity, get a flawed
program, hit **Play**, fix bugs and smells, hit **Finish** and get scored.

Requires Neovim 0.10+. Works with whatever you already have: the exercise is a real file
(`<data>/learn-refactor/workspace/<id>/main.<ext>`), so LSP, treesitter, formatters, completion and linters attach normally.
Pickers use `vim.ui.select` (telescope-ui-select, snacks, dressing, fzf-lua... take over automatically).

## Install (lazy.nvim / LazyVim)

Copy [`examples/lazy.lua`](examples/lazy.lua) to `~/.config/nvim/lua/plugins/learn-refactor.lua`
(LazyVim and any setup that imports `plugins`), then `:Lazy sync`. It lazy-loads on the commands and the
`<leader>R` keys, and registers a which-key group. Minimal version:

```lua
{
  "dev-vinicius-andrade/nvim-learn-refactor",
  cmd = { "Refactor", "RefactorLibrary", "RefactorStats", "RefactorConfigTips" },
  keys = { { "<leader>Rr", "<cmd>Refactor<cr>", desc = "Refactor: start challenge" } },
  opts = { keymaps = false },
}
```

Local checkout: use `dir = "~/path/to/nvim-learn-refactor"` instead of the repo name. Packer/vim-plug/`vim.pack` also
work: any manager that puts the repo on the runtimepath, then `require("learn_refactor").setup()` (optional).

Challenge generation uses the Anthropic API via `curl`: `export ANTHROPIC_API_KEY=...`.
Without a key (or on failure) it falls back to your saved library, then built-in seeds. Run `:checkhealth learn-refactor`.

### Cheaper / free models

`provider = "openai"` talks to any OpenAI-compatible endpoint (Ollama, LM Studio, OpenRouter, Groq, ...).
`routes` picks provider/model per complexity, anything unset falls back to the global settings:

```lua
opts = {
  provider = "openai",
  openai = { base_url = "http://localhost:11434/v1", model = "qwen2.5-coder:14b" }, -- local, free
  routes = {
    hard   = { provider = "anthropic", model = "claude-sonnet-5-5" },
    expert = { provider = "anthropic", model = "claude-sonnet-5-5" },
    easy   = { provider = "anthropic", model = "claude-haiku-5-5" },
  },
}
```

Weak models are handled: generated checks that do not compile, or that already pass on the original code, are dropped.

### Local Ollama in a container (podman or docker, optional GPU)

`docker/compose.yaml` runs Ollama bound to `127.0.0.1` with a persistent model volume; `compose.gpu.yaml` (podman/CDI)
and `compose.gpu-docker.yaml` add an NVIDIA GPU. The plugin picks podman or docker, enables the GPU override when
it is available (`ollama.gpu = "auto"`), starts the container, waits for the API and pulls the model:

```lua
opts = {
  provider = "openai",   -- talks to http://localhost:11434/v1 by default
  ollama = { model = "qwen2.5-coder:14b", auto_start = true }, -- start on demand when generating
}
```

`:RefactorOllama up | down | status | pull`. `down` keeps the model volume. `qwen2.5-coder:14b` (~9 GB) suits a 12-16 GB GPU;
use `:7b` for 8 GB or less, and expect weaker JSON/tests from small models (bad ones are dropped, see Scoring integrity).

GPU with podman needs a CDI spec once per host (also on WSL2, with the Windows NVIDIA driver):

```bash
sudo pacman -S nvidia-container-toolkit   # or apt/dnf equivalent
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Usage

| Command | Action |
|---|---|
| `:Refactor [lang] [complexity] [library]` | menu, or direct start |
| `:RefactorPlay` / `Pause` / `Stop` / `Finish` | session control (also clickable bar, top-right) |
| `:RefactorHint` | reveal next bug hint (-5 pts) |
| `:RefactorLibrary` | replay a saved challenge |
| `:RefactorStats` | points + weakest topics |
| `:RefactorConfigTips` | suggestions to improve your own Neovim setup |

Default keymaps (set `keymaps = false`, or one entry to `false`, to skip): `<leader>Rr` start, `Rl` library, `Rp` play, `RP` pause, `Rs` stop, `Rf` finish, `Rh` hint, `Rt` setup tips.

Statusline: `require("learn_refactor").statusline()`. Events: `User LearnRefactorOpen|Play|Pause|Stop|Finish`.

## Scoring

- Bugs found/fixed (check per bug), best-practice rules (naming, duplication, magic numbers, idioms...)
- Optional `run_cmd` behaviour check (+40), no LSP errors (+10), speed bonus vs par time (+15)
- Clean motions bonus (+10); penalty per arrow key, mouse click, or `hjkl` repeated >4x (max -15); hints cost points

## Coaching and setup tips

On finish you also get:

- **Motion coach**: patterns found in your keystrokes with the better alternative, e.g. "8 j/k presses in long runs: use `12j`, `}`, `/pattern`", long `w` chains, `x` runs, backspace runs, arrows, mouse. After a long session it lists features you never used (text objects, `.`, `*`, `%`, macros).
- **Your setup**: suggestions from your own config, tied to what happened in the session: options (`relativenumber`, `scrolloff`, `smartcase`, `inccommand`, `undofile`, `mouse`...), missing plugin categories (jump, surround, text objects, which-key, fuzzy finder, formatter, treesitter; installed plugins are detected via lazy.nvim or the runtimepath), and LSP refactoring keys. It only reports; it never changes your config. `:RefactorConfigTips` shows the full list any time.
- `s` in the result window opens the reference solution when the model provided one.

## Scoring integrity

- Models also write a reference `solution` and hidden `tests` (plain asserts, run through `languages.<lang>.test`). Tests are kept only if they pass on that solution, and bug checks must hold on the solution too; otherwise they are dropped, so you are never punished for a broken test.
- If hidden tests fail on your result, bug/standard credit is halved; if they pass you get +40.
- Deleting most of the code (below `min_code_ratio`, default 35% of the original non-blank lines) or changing nothing scores 0.

## Security

Challenge code and hidden tests are written by a model and **run on your machine** when you finish (never at generation time, except the validation run of tests against the reference solution). Model-supplied shell commands and ids are ignored: only the command in `languages.<lang>.test` is executed, in a temp directory with a 15s timeout. It is not a sandbox. Set `run_tests = false` to disable, or point `test` at a container/sandbox wrapper.

## Adaptive generation

Every saved challenge goes to `challenges/*.json`. Results update `profile.json` (pass rate per topic) and
`history.json`. The next prompt tells the model your weak/strong topics, recent results, and titles to avoid repeating.

Storage is plain JSON files in `stdpath("data")/learn-refactor` (`data_dir` option).

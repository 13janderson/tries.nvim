# tries.nvim

Per-project scratch scripts, called **tries**, for Neovim.

A try is a small, disposable workspace for experimenting with code without
creating test files inside the current project. Tries are scaffolded by
language, tracked with JSON state, opened in their own tab, and listed through
Telescope.

> **Status:** work in progress, extracted from a personal Neovim config. The
> module namespace has not been repackaged for standalone installation yet.

## What works today

### Creating tries

- `T` opens a Telescope picker of supported language choices.
- `:TryNew [language]` creates a script try directly.
- `:TryProject [language]` creates a project try directly.
- `:Tries` opens the list of tries for the current working directory.
- `<C-t>` is the keymap equivalent of `:Tries`.

Picker choices are coloured with their real `nvim-web-devicons` glyphs and
highlight groups.

Each language offers a **script** choice. Python, TypeScript, and Go also offer
a **project** choice:

| Choice | How it is created |
| --- | --- |
| Python script | Executable `main.py` (PEP 723/uv shebang when `uv` is available, otherwise `python3`) |
| Python project | `uv init --name <slug>`; fails if `uv` is absent |
| TypeScript script | Executable `main.ts` with a Bun shebang |
| TypeScript project | `bun init -y`; uses `index.ts` |
| JavaScript script | Executable `main.js` with a Node shebang |
| Bash script | Executable `#!/usr/bin/env bash` script |
| Go script | Executable `main.go` using the standard shell/Go polyglot first line |
| Go project | `go mod init <slug>` followed by the Go script scaffold |

The Go polyglot avoids a literal `#!` line because Go rejects it:

```go
//usr/bin/env go run "$0" "$@"; exit $?
```

### Storage and state

Tries live in a configurable external directory:

```lua
require('custom.my.tries').setup {
  try_dir = '~/src/tries/nvim',
}
```

Each try gets its own directory:

```text
<TRY_DIR>/
  .try/
    <sha256-of-cwd>.json
  2026-11-19-221303-go-project/
    main.go
  2026-11-19-221305-python-project/
    main.py
    pyproject.toml
    ...
```

A state file is keyed by the SHA-256 hash of the working directory in which the
try was created. It records the try name, language, kind, directory,
entrypoint, and creation time. State is written with `vim.json.encode`.

### Tabs and cwd

Every try opens in its own tab. The tab is scoped with `:tcd` to the try
directory, so new splits and terminals in that tab inherit the same working
directory. Reopening a try from the list switches back to its existing tab
instead of creating a duplicate. Closing the tab allows a fresh one to be
created later.

### Design

- `TryLanguage` is an OOP-ish base class with language metadata and
  `scaffold(ctx)` / `scaffold_project(ctx)` hooks.
- A language scaffolds an entrypoint into `ctx.dir` and returns the entrypoint
  path relative to that directory.
- The framework owns directory creation, state, listing, tabs, and opening.
- Languages are explicitly registered in `languages/init.lua`.
- LuaCATS annotations are used throughout for LuaLS.

Current library layout (dotfiles-era):

```text
init.lua
language.lua
tries.lua
languages/
  init.lua
  bash.lua
  go.lua
  javascript.lua
  python.lua
  typescript.lua
```

## Requirements

- Neovim with `vim.json`, `vim.system`, and tab-local cwd support (recent 0.10+;
  developed against 0.12).
- [Telescope](https://github.com/nvim-telescope/telescope.nvim)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
- Language tools as needed:
  - `uv` for Python projects (Python scripts fall back to `python3`)
  - `bun` for TypeScript projects
  - `go` for Go projects
  - `node` for JavaScript scripts
  - `bash` for Bash scripts

## Known gaps / next steps

### Repackage as a standalone plugin

The code still uses the `custom.my.tries.*` module namespace and a shim
`init.lua` from the original dotfiles setup. Before installing it as a normal
plugin it should move under:

```text
lua/tries/init.lua
lua/tries/language.lua
lua/tries/tries.lua
lua/tries/languages/...
```

and the `require` paths should become `tries.*`.

### Local tries (parked)

The next planned feature is creating a try inside the current working directory
so it can import surrounding project code:

- `CR` in the picker creates an external try under `TRY_DIR`.
- `C-l` creates a local try under `<cwd>/.try/<timestamp>-<slug>/`.
- Local tabs should be `:tcd`'d to the project root.
- `.try/.gitignore` containing `*` should keep local tries out of `git status`.
- Local scope should apply to scripts only, not project-kind tries.
- Python local imports need a decision: a root-level entrypoint, a generated
  `sys.path` bootstrap, or some other layout.

### Running tries

Not implemented yet. The planned direction is to keep run behaviour on the
language implementation, even though every try has an entrypoint:

- run a script by its entrypoint,
- run a project in a language-appropriate way,
- later add per-language configuration/templates, such as an asyncio Python
  scaffold.

See [`notes.md`](notes.md) for the raw working notes on this.

### Tests

There is no automated test suite yet. The implementation has been exercised
headlessly against temporary `TRY_DIR`s: creation for every language, project
scaffolds, state shape, listing, coloured picker highlights, executable bits,
Go polyglot execution, and per-tab cwd isolation.

## License

No license has been chosen yet.

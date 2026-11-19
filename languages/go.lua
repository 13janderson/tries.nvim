local Language = require 'custom.my.tries.language'

---@type TryLanguage
local Go = Language.new {
  _id = 'go',
  _label = 'Go',
  _extension = 'go',
  filetype = 'go',
  icon = vim.fn.nr2char(0xE627),
  icon_hl = 'DevIconGo',
}

-- TODO(scaffold): add Go-specific scaffolding.
---Go rejects a literal `#!` line, so use the standard shell/Go polyglot:
---the first line is a Go comment and a shell command. `go run` still works.
---@param ctx TryContext
---@return string
function Go:scaffold(ctx)
  local entrypoint = 'main.go'
  local path = self:write_file(ctx, entrypoint, {
    '//usr/bin/env go run "$0" "$@"; exit $?',
    '',
    'package main',
    '',
    'import "fmt"',
    '',
    'func main() {',
    '\tfmt.Println("TODO: Go try: ' .. ctx.name .. '")',
    '}',
  })
  self:make_executable(path)
  return entrypoint
end

---@param ctx TryContext
---@return string
function Go:scaffold_project(ctx)
  self:require_executable 'go'
  self:run(ctx, { 'go', 'mod', 'init', ctx.slug })
  return self:scaffold(ctx)
end

return Go

local Language = require 'custom.my.tries.language'

---@type TryLanguage
local TypeScript = Language.new {
  _id = 'typescript',
  _label = 'TypeScript',
  _extension = 'ts',
  filetype = 'typescript',
  icon = vim.fn.nr2char(0xE628),
  icon_hl = 'DevIconTypeScript',
}

-- TODO(scaffold): add TypeScript-specific scaffolding (e.g. dependencies).
---Bun runs TypeScript directly; no package.json is required.
---@param ctx TryContext
---@return string
function TypeScript:scaffold(ctx)
  local entrypoint = 'main.ts'
  local path = self:write_file(ctx, entrypoint, {
    '#!/usr/bin/env bun',
    '// TODO: TypeScript try: ' .. ctx.name,
  })
  self:make_executable(path)
  return entrypoint
end

---@param ctx TryContext
---@return string
function TypeScript:scaffold_project(ctx)
  self:require_executable 'bun'
  self:run(ctx, { 'bun', 'init', '-y' })

  if vim.fn.filereadable(ctx.dir .. '/index.ts') == 0 then
    error 'bun init did not create index.ts'
  end
  return 'index.ts'
end

return TypeScript

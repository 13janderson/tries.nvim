local Language = require 'custom.my.tries.language'

---@type TryLanguage
local Python = Language.new {
  _id = 'python',
  _label = 'Python',
  _extension = 'py',
  filetype = 'python',
  icon = vim.fn.nr2char(0xE606),
  icon_hl = 'DevIconPy',
}

-- TODO(scaffold): add Python-specific scaffolding (e.g. PEP 723 dependency metadata).
---@param ctx TryContext
---@return string
function Python:scaffold(ctx)
  local shebang = vim.fn.executable 'uv' == 1 and '#!/usr/bin/env -S uv run --script' or '#!/usr/bin/env python3'

  local entrypoint = 'main.py'
  local path = self:write_file(ctx, entrypoint, {
    shebang,
    '',
    '# TODO: Python try: ' .. ctx.name,
  })
  self:make_executable(path)
  return entrypoint
end

---@param ctx TryContext
---@return string
function Python:scaffold_project(ctx)
  self:require_executable 'uv'
  self:run(ctx, { 'uv', 'init', '--name', ctx.slug })

  if vim.fn.filereadable(ctx.dir .. '/main.py') == 0 then
    error 'uv init did not create main.py'
  end
  return 'main.py'
end

return Python

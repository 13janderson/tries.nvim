local Language = require 'custom.my.tries.language'

---@type TryLanguage
local JavaScript = Language.new {
  _id = 'javascript',
  _label = 'JavaScript',
  _extension = 'js',
  filetype = 'javascript',
  icon = vim.fn.nr2char(0xE60C),
  icon_hl = 'DevIconJs',
}

-- TODO(scaffold): add JavaScript-specific scaffolding (e.g. dependencies).
---@param ctx TryContext
---@return string
function JavaScript:scaffold(ctx)
  local entrypoint = 'main.js'
  local path = self:write_file(ctx, entrypoint, {
    '#!/usr/bin/env node',
    '// TODO: JavaScript try: ' .. ctx.name,
  })
  self:make_executable(path)
  return entrypoint
end

return JavaScript

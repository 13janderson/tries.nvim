local Language = require 'custom.my.tries.language'

---@type TryLanguage
local Bash = Language.new {
  _id = 'bash',
  _label = 'Bash',
  _extension = 'sh',
  filetype = 'sh',
  icon = vim.fn.nr2char(0xE760),
  icon_hl = 'DevIconBash',
}

-- TODO(scaffold): add Bash-specific scaffolding.
---@param ctx TryContext
---@return string
function Bash:scaffold(ctx)
  local entrypoint = ctx.slug .. '.sh'
  local path = self:write_file(ctx, entrypoint, {
    '#!/usr/bin/env bash',
    '# TODO: Bash try: ' .. ctx.name,
  })
  self:make_executable(path)
  return entrypoint
end

return Bash

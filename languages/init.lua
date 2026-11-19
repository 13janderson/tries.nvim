---@class TryLanguageRegistry
local M = {}

---Concrete, ordered list of supported languages.
---@type TryLanguage[]
local languages = {
  require 'custom.my.tries.languages.python',
  require 'custom.my.tries.languages.typescript',
  require 'custom.my.tries.languages.javascript',
  require 'custom.my.tries.languages.bash',
  require 'custom.my.tries.languages.go',
}

---@type table<string, TryLanguage>
local by_id = {}
for _, language in ipairs(languages) do
  by_id[language:id()] = language
end

---@return TryLanguage[]
function M.all()
  return languages
end

---@param id string
---@return TryLanguage|nil
function M.get(id)
  return by_id[id]
end

return M

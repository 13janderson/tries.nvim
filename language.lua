---Context passed to a language when scaffolding a new try.
---@class TryContext
---@field cwd string Absolute working directory the try was created from.
---@field name string Slugified try name.
---@field slug string Slugified try name.
---@field dir string Absolute path to the try directory. The language owns its contents.
---@field root string Configured TRY_DIR.
---@field timestamp string ISO-8601 creation timestamp.

---Base class for a try language.
---
---A language is responsible for two things:
---  1. describing itself (id, label, extension, filetype, icon)
---  2. scaffolding a new try into `ctx.dir` and returning its entrypoint
---@class TryLanguage
---@field _id string
---@field _label string
---@field _extension string
---@field filetype string
---@field icon string
---@field icon_hl string
local Language = {}
Language.__index = Language

---@param opts { _id: string, _label: string, _extension: string, filetype: string, icon: string, icon_hl: string }
---@return TryLanguage
function Language.new(opts)
  return setmetatable(opts, Language)
end

---@return string
function Language:id()
  return self._id
end

---@return string
function Language:label()
  return self._label
end

---@return string
function Language:extension()
  return self._extension
end

---Write one file inside the try directory, creating parent directories.
---@param ctx TryContext
---@param relative_path string
---@param lines string[]
---@return string path Absolute path to the written file.
function Language:write_file(ctx, relative_path, lines)
  local path = ctx.dir .. '/' .. relative_path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')

  local wrote = vim.fn.writefile(lines, path)
  if wrote ~= 0 then
    error('could not write ' .. path)
  end
  return path
end

---Mark a file executable (0755).
---@param path string
function Language:make_executable(path)
  local ok, err = vim.uv.fs_chmod(path, 493)
  if not ok then
    error('could not chmod ' .. path .. ': ' .. tostring(err))
  end
end

---Run a command with `ctx.dir` as its working directory.
---Raises on a non-zero exit code.
---@param ctx TryContext
---@param cmd string[]
---@return string output
function Language:run(ctx, cmd)
  local result = vim.system(cmd, { cwd = ctx.dir, text = true }):wait()
  local output = vim.trim((result.stdout or '') .. (result.stderr or ''))
  if result.code ~= 0 then
    error(string.format('%s failed (%d): %s', table.concat(cmd, ' '), result.code, output))
  end
  return output
end

---Raise unless `name` is available on PATH.
---@param name string
function Language:require_executable(name)
  if vim.fn.executable(name) ~= 1 then
    error(name .. ' is not installed')
  end
end

---Scaffold a new try into `ctx.dir`.
---Must return the entrypoint path relative to `ctx.dir`.
---@param _ctx TryContext
---@return string
function Language:scaffold(_ctx)
  error('scaffold not implemented for ' .. self._id)
end

---Scaffold a new project into `ctx.dir`.
---Languages override this when they support project creation.
---Must return the entrypoint path relative to `ctx.dir`.
---@param _ctx TryContext
---@return string
function Language:scaffold_project(_ctx)
  error('project scaffolding not supported for ' .. self._id)
end

---@return boolean
function Language:supports_project()
  return self.scaffold_project ~= Language.scaffold_project
end

return Language

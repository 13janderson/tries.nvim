-- A try is something we can create.
--
--
--

-- want the ability new try and presents you with a telescope picker of supported language options.
-- when making a new try and picking a language, each language should have it's own custom implementation for how to create a try.
-- leave these scaffolded for now. we probably want to do some OOP here.
-- upon making a selection, a new try is scaffolded and saved in the configurable try output directory - called TRY_DIR for now.
-- on making a try we also save some JSON state within a .try directory of TRY_DIR under the file which is the hash of the
-- current working directory. use neovim/luas inherent table to json serialisation functionality.
-- we should then have a way to list tries for a directory - this should just do lookup withint the TRY_DIR with the same hashing as described above.
-- expose the functions needed for the above basic API.

---@alias TryKind 'script'|'project'

---@class TriesConfig
---@field try_dir string

---@class TryEntry
---@field name string
---@field dir string Directory name relative to TRY_DIR.
---@field entrypoint string Entrypoint path relative to `dir`.
---@field language string
---@field kind TryKind
---@field created string

---@class TryChoice
---@field language TryLanguage
---@field kind TryKind
---@field label string

---@class TriesState
---@field cwd string
---@field tries TryEntry[]

---@class Tries
---@field config TriesConfig
local M = {}

---@type TriesConfig
M.config = {
  -- Configurable output directory for scaffolded tries and their JSON state.
  try_dir = vim.fn.expand '~/src/tries/nvim',
}

local languages = require 'custom.my.tries.languages'

---@return string
local function try_dir()
  return vim.fn.expand(M.config.try_dir)
end

---@param cwd string|nil
---@return string
local function normalize_cwd(cwd)
  return vim.fs.normalize(vim.fn.fnamemodify(cwd or vim.uv.cwd() or '.', ':p'))
end

---@return string
local function iso_now()
  return tostring(os.date '%Y-%m-%dT%H:%M:%S')
end

---@param name string|nil
---@return string
local function slugify(name)
  local slug = tostring(name or ''):lower():gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
  if slug == '' then
    slug = 'try'
  end
  return slug:sub(1, 48)
end

---Configure the tries module. Currently only `try_dir` is supported.
---@param opts { try_dir?: string }|nil
function M.setup(opts)
  opts = opts or {}
  if opts.try_dir then
    M.config.try_dir = opts.try_dir
  end
end

---Return the stable key used for a project's state file.
---@param cwd string|nil
---@return string
function M.hash(cwd)
  return vim.fn.sha256(normalize_cwd(cwd))
end

---Return the path to the JSON state file for a project's cwd.
---@param cwd string|nil
---@return string
function M.state_path(cwd)
  return try_dir() .. '/.try/' .. M.hash(cwd) .. '.json'
end

---Read the persisted state for a cwd. Returns a fresh state on first use.
---@param cwd string|nil
---@return TriesState
function M.read_state(cwd)
  cwd = normalize_cwd(cwd)
  local path = M.state_path(cwd)

  local ok, lines = pcall(vim.fn.readfile, path)
  if ok and type(lines) == 'table' and #lines > 0 then
    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if decoded_ok and type(decoded) == 'table' then
      ---@cast decoded TriesState
      if type(decoded.tries) ~= 'table' then
        decoded.tries = {}
      end
      for _, entry in ipairs(decoded.tries) do
        ---@cast entry TryEntry
        if not entry.kind then
          entry.kind = 'script'
        end
      end
      if not decoded.cwd then
        decoded.cwd = cwd
      end
      return decoded
    end
  end

  return { cwd = cwd, tries = {} }
end

---Persist state for a cwd using vim.json.encode.
---@param state TriesState
---@return boolean
function M.write_state(state)
  local path = M.state_path(state.cwd)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')

  local wrote = vim.fn.writefile({ vim.json.encode(state) }, path)
  if wrote ~= 0 then
    vim.notify('Tries: could not write state to ' .. path, vim.log.levels.ERROR)
    return false
  end
  return true
end

---@param root string
---@param slug string
---@return string
local function unique_dir(root, slug)
  local base = tostring(os.date '%Y-%m-%d-%H%M%S') .. '-' .. slug
  local name = base
  local i = 2
  while vim.uv.fs_stat(root .. '/' .. name) do
    name = base .. '-' .. i
    i = i + 1
  end
  return name
end

---Validate and relativise the entrypoint returned by a language.
---@param dir string
---@param entrypoint any
---@return string|nil relative_path
---@return string|nil err
local function relative_entrypoint(dir, entrypoint)
  if type(entrypoint) ~= 'string' or entrypoint == '' then
    return nil, 'scaffold must return a non-empty entrypoint'
  end

  local absolute
  if entrypoint:sub(1, 1) == '/' then
    absolute = vim.fs.normalize(entrypoint)
  else
    absolute = vim.fs.normalize(dir .. '/' .. entrypoint)
  end

  local root = vim.fs.normalize(dir)
  if not vim.startswith(absolute, root .. '/') then
    return nil, 'entrypoint must stay inside the try directory'
  end

  local stat = vim.uv.fs_stat(absolute)
  if not stat or stat.type ~= 'file' then
    return nil, 'entrypoint does not exist or is not a file'
  end

  return absolute:sub(#root + 2)
end

---@type table<string, integer>
local try_tabs = {}

---@param path string
local function open_path(path)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified or vim.bo[buf].buftype ~= '' then
    vim.cmd('tabedit ' .. vim.fn.fnameescape(path))
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end
end

---Resolve the absolute entrypoint for a try entry.
---@param entry TryEntry
---@return string|nil
function M.entry_path(entry)
  if not entry.dir or not entry.entrypoint then
    return nil
  end

  local root = vim.fs.normalize(try_dir())
  local path = vim.fs.normalize(root .. '/' .. entry.dir .. '/' .. entry.entrypoint)
  if not vim.startswith(path, root .. '/') then
    return nil
  end
  return path
end

---Find the tab already associated with a try directory, if any.
---@param dir string
---@return integer|nil
local function find_try_tab(dir)
  local tab = try_tabs[dir]
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    return tab
  end

  for _, candidate in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, value = pcall(vim.api.nvim_tabpage_get_var, candidate, 'try_dir')
    if ok and value == dir then
      try_tabs[dir] = candidate
      return candidate
    end
  end
end

---Switch to (or create) a tab scoped to a try directory.
---@param dir string
---@return integer
local function ensure_try_tab(dir)
  local tab = find_try_tab(dir)
  if tab then
    vim.api.nvim_set_current_tabpage(tab)
  else
    vim.cmd 'tabnew'
    tab = vim.api.nvim_get_current_tabpage()
    try_tabs[dir] = tab
    vim.api.nvim_tabpage_set_var(tab, 'try_dir', dir)
  end

  -- Tab-local cwd: every window in this tab (and new splits/terminals) uses it.
  vim.cmd('tcd ' .. vim.fn.fnameescape(dir))
  return tab
end

---Find a window in the current tab showing `path`.
---@param path string
---@return integer|nil
local function win_for_path(path)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(buf) == path then
      return win
    end
  end
end

---Open `path` inside the current tab without leaving the tab.
---@param path string
local function open_in_try_tab(path)
  local win = win_for_path(path)
  if win then
    vim.api.nvim_set_current_win(win)
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified or vim.bo[buf].buftype ~= '' then
    vim.cmd('split ' .. vim.fn.fnameescape(path))
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end
end

---Open a try entry in its own tab, or a path in the current tab.
---@param entry TryEntry|string
function M.open(entry)
  if type(entry) == 'table' then
    local path = M.entry_path(entry)
    if not path then
      vim.notify('Tries: entry has no resolvable entrypoint', vim.log.levels.ERROR)
      return
    end

    local dir = vim.fs.normalize(try_dir() .. '/' .. entry.dir)
    if vim.fn.isdirectory(dir) == 0 then
      vim.notify('Tries: try directory is missing: ' .. vim.fn.fnamemodify(dir, ':~'), vim.log.levels.ERROR)
      return
    end

    ensure_try_tab(dir)
    open_in_try_tab(path)

    local language = languages.get(entry.language)
    if language and language.filetype then
      vim.bo.filetype = language.filetype
    end
    return
  end

  ---@cast entry string
  open_path(entry)
end

---Scaffold, save and open a new try for a language.
---The language owns the contents of the try directory and returns its entrypoint.
---@param language TryLanguage
---@param name string
---@param cwd string|nil
---@param kind TryKind|nil
---@return TryEntry|nil
function M.create(language, name, cwd, kind)
  kind = kind or 'script'
  if kind == 'project' and not language:supports_project() then
    vim.notify('Tries: ' .. language:label() .. ' does not support project creation', vim.log.levels.ERROR)
    return
  end

  cwd = normalize_cwd(cwd)
  local root = try_dir()
  vim.fn.mkdir(root, 'p')

  local slug = slugify(name)
  local dir_name = unique_dir(root, slug)
  local dir = root .. '/' .. dir_name
  vim.fn.mkdir(dir, 'p')

  ---@type TryContext
  local ctx = {
    cwd = cwd,
    name = slug,
    slug = slug,
    dir = dir,
    root = root,
    timestamp = iso_now(),
  }

  local ok, entrypoint
  if kind == 'project' then
    ok, entrypoint = pcall(language.scaffold_project, language, ctx)
  else
    ok, entrypoint = pcall(language.scaffold, language, ctx)
  end

  if not ok then
    vim.fn.delete(dir, 'rf')
    vim.notify('Tries: ' .. language:id() .. ' ' .. kind .. ' scaffold failed: ' .. tostring(entrypoint), vim.log.levels.ERROR)
    return
  end

  local relative, err = relative_entrypoint(dir, entrypoint)
  if not relative then
    vim.fn.delete(dir, 'rf')
    vim.notify('Tries: ' .. language:id() .. ' ' .. kind .. ' scaffold failed: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  ---@type TryEntry
  local entry = {
    name = slug,
    dir = dir_name,
    entrypoint = relative,
    language = language:id(),
    kind = kind,
    created = iso_now(),
  }

  local state = M.read_state(cwd)
  state.tries[#state.tries + 1] = entry
  M.write_state(state)

  M.open(entry)
  vim.notify('Try created: ' .. vim.fn.fnamemodify(M.entry_path(entry) or dir, ':~'), vim.log.levels.INFO)
  return entry
end

---Return the concrete list of supported languages, in picker order.
---@return TryLanguage[]
function M.languages()
  return languages.all()
end

---Look up a supported language by id.
---@param id string
---@return TryLanguage|nil
function M.language(id)
  return languages.get(id)
end

---Resolve icons and define their highlight groups lazily.
---nvim-web-devicons creates the DevIcon* groups when get_icon is called.
local function ensure_icons()
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if not ok then
    return
  end

  for _, language in ipairs(languages.all()) do
    local ext = language:extension()
    local icon, hl = devicons.get_icon('try.' .. ext, ext)
    if icon and icon ~= '' then
      language.icon = icon
    end
    if hl and hl ~= '' then
      language.icon_hl = hl
    end
  end
end

---Return the concrete picker choices.
---Every language offers a script; languages that support projects offer both.
---@param kind TryKind|nil
---@return TryChoice[]
function M.choices(kind)
  local choices = {}
  for _, language in ipairs(languages.all()) do
    if kind == nil or kind == 'script' then
      choices[#choices + 1] = {
        language = language,
        kind = 'script',
        label = language:label() .. ' script',
      }
    end
    if (kind == nil or kind == 'project') and language:supports_project() then
      choices[#choices + 1] = {
        language = language,
        kind = 'project',
        label = language:label() .. ' project',
      }
    end
  end
  return choices
end

---@param choice TryChoice
---@return string
local function choice_display(choice)
  return string.format('%s  %s', choice.language.icon, choice.label)
end

---@param choices TryChoice[]
---@param cb fun(choice: TryChoice|nil)
local function pick_choice(choices, cb)
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(choices, {
      prompt = 'New try',
      format_item = choice_display,
    }, cb)
    return
  end

  ensure_icons()

  local entry_display = require 'telescope.pickers.entry_display'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local conf = require('telescope.config').values

  local icon_width = 1
  for _, choice in ipairs(choices) do
    icon_width = math.max(icon_width, vim.fn.strdisplaywidth(choice.language.icon))
  end

  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = icon_width },
      { remaining = true },
    },
  }

  pickers
    .new({}, {
      prompt_title = 'New try',
      finder = finders.new_table {
        results = choices,
        entry_maker = function(choice)
          return {
            value = choice,
            icon = choice.language.icon,
            icon_hl = choice.language.icon_hl,
            label = choice.label,
            ordinal = choice.label .. ' ' .. choice.language:id(),
            display = function(entry)
              return displayer {
                { entry.icon, entry.icon_hl },
                { entry.label },
              }
            end,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.schedule(function()
              cb(selection.value)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

---List persisted tries for a cwd, newest first. Missing files are skipped.
---@param cwd string|nil
---@return TryEntry[]
function M.list_for_cwd(cwd)
  cwd = normalize_cwd(cwd)
  local state = M.read_state(cwd)
  local tries = {}

  for _, entry in ipairs(state.tries) do
    local path = M.entry_path(entry)
    if path and vim.uv.fs_stat(path) then
      tries[#tries + 1] = entry
    end
  end

  table.sort(tries, function(a, b)
    return (a.created or '') > (b.created or '')
  end)
  return tries
end

---@param entry TryEntry
---@return string
local function display_try(entry)
  local created = entry.created and entry.created:gsub('T', ' '):sub(1, 16) or ''
  return string.format('%s [%s %s] %s', entry.name or '?', entry.language or '?', entry.kind or 'script', created)
end

---Browse tries for a cwd with Telescope.
---@param opts { cwd?: string }|nil
function M.list(opts)
  opts = opts or {}
  local cwd = normalize_cwd(opts.cwd)
  local tries = M.list_for_cwd(cwd)
  if #tries == 0 then
    vim.notify('Tries: none for ' .. vim.fn.fnamemodify(cwd, ':~') .. ' (press T to create one)', vim.log.levels.INFO)
    return
  end

  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(tries, {
      prompt = 'Tries',
      format_item = display_try,
    }, function(entry)
      if entry then
        M.open(entry)
      end
    end)
    return
  end

  local entry_display = require 'telescope.pickers.entry_display'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local conf = require('telescope.config').values

  ensure_icons()

  local icon_width = 1
  for _, entry in ipairs(tries) do
    local language = languages.get(entry.language)
    if language then
      icon_width = math.max(icon_width, vim.fn.strdisplaywidth(language.icon))
    end
  end

  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = icon_width },
      { remaining = true },
    },
  }

  pickers
    .new({}, {
      prompt_title = 'Tries [' .. vim.fn.fnamemodify(cwd, ':~') .. ']',
      finder = finders.new_table {
        results = tries,
        entry_maker = function(entry)
          local language = languages.get(entry.language)
          return {
            value = entry,
            icon = language and language.icon or '',
            icon_hl = language and language.icon_hl or 'Normal',
            text = display_try(entry),
            ordinal = (entry.name or '') .. ' ' .. (entry.language or '') .. ' ' .. (entry.kind or 'script'),
            path = M.entry_path(entry),
            display = function(e)
              return displayer {
                { e.icon, e.icon_hl },
                { e.text },
              }
            end,
          }
        end,
      },
      previewer = conf.file_previewer {},
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.schedule(function()
              M.open(selection.value)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

---Create a new try. With no language, opens the Telescope picker of scripts/projects.
---@param opts { language?: string, name?: string, cwd?: string, kind?: TryKind }|nil
function M.new(opts)
  opts = opts or {}

  ---@param choice TryChoice|nil
  local function with_choice(choice)
    if not choice then
      return
    end
    if opts.name then
      M.create(choice.language, opts.name, opts.cwd, choice.kind)
      return
    end
    vim.ui.input({ prompt = 'Try name: ' }, function(name)
      if name == nil then
        return
      end
      M.create(choice.language, name, opts.cwd, choice.kind)
    end)
  end

  if opts.language then
    local language = M.language(opts.language)
    if not language then
      vim.notify('Tries: unsupported language ' .. tostring(opts.language), vim.log.levels.ERROR)
      return
    end

    local kind = opts.kind or 'script'
    if kind == 'project' and not language:supports_project() then
      vim.notify('Tries: ' .. language:label() .. ' does not support project creation', vim.log.levels.ERROR)
      return
    end

    with_choice { language = language, kind = kind, label = language:label() .. ' ' .. kind }
    return
  end

  pick_choice(M.choices(opts.kind), with_choice)
end

-- Public keymaps: uppercase T is still unused by the rest of the config.
vim.keymap.set('n', 'T', function()
  M.new()
end, { desc = 'Tries: new' })

vim.keymap.set('n', '<C-t>', function()
  M.list()
end, { desc = 'Tries: list for cwd' })

vim.api.nvim_create_user_command('TryNew', function(args)
  M.new { language = args.args ~= '' and args.args or nil, kind = 'script' }
end, { nargs = '?', desc = 'Create a new try script' })

vim.api.nvim_create_user_command('TryProject', function(args)
  M.new { language = args.args ~= '' and args.args or nil, kind = 'project' }
end, { nargs = '?', desc = 'Create a new try project' })

vim.api.nvim_create_user_command('Tries', function()
  M.list()
end, { desc = 'List tries for the current directory' })

-- Drop stale in-memory tab handles when a try tab is closed.
vim.api.nvim_create_autocmd('TabClosed', {
  group = vim.api.nvim_create_augroup('TriesTabs', { clear = true }),
  callback = function()
    for dir, tab in pairs(try_tabs) do
      if not vim.api.nvim_tabpage_is_valid(tab) then
        try_tabs[dir] = nil
      end
    end
  end,
})

return M

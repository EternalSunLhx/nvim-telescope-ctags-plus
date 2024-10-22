-- The idea is to create a picker that replaces the functionality of `g[` in vim.

local actions = require "telescope.actions"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local previewers = require "telescope.previewers"
local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local utils = require "telescope.utils"
local conf = require("telescope.config").values
local entry_display = require "telescope.pickers.entry_display"

local flatten = vim.tbl_flatten
local Path = require "plenary.path"

local ctags_plus = {}

local handle_entry_index = function(opts, t, k)
  local override = ((opts or {}).entry_index or {})[k]
  if not override then
    return
  end

  local val, save = override(t, opts)
  if save then
    rawset(t, k, val)
  end
  return val
end

local function gen_from_ctags(opts)
  opts = opts or {}

  local show_kind = vim.F.if_nil(opts.show_kind, true)
  local cwd = utils.path_expand(opts.cwd or vim.loop.cwd())
  local current_file = Path:new(vim.api.nvim_buf_get_name(opts.bufnr)):normalize(cwd)

  local display_items = {
    { width = 16 },
    { remaining = true },
  }

  local idx = 1
  local hidden = utils.is_path_hidden(opts)
  if not hidden then
    table.insert(display_items, idx, { width = vim.F.if_nil(opts.fname_width, 30) })
    idx = idx + 1
  end

  if opts.show_line then
    table.insert(display_items, idx, { width = 30 })
  end

  local displayer = entry_display.create {
    separator = " │ ",
    items = display_items,
  }

  local make_display = function(entry)
    local display_path, path_style = utils.transform_path(opts, entry.filename)

    local scode
    if opts.show_line then
      scode = entry.scode
    end

    if hidden then
      return displayer {
        entry.tag,
        scode,
      }
    else
      return displayer {
        {
          display_path,
          function()
            return path_style or {}
          end,
        },
        entry.tag,
        entry.kind,
        scode,
      }
    end
  end

  local mt = {}
  mt.__index = function(t, k)
    local override = handle_entry_index(opts, t, k)
    if override then
      return override
    end

    if k == "path" then
      local retpath = Path:new({ t.filename }):absolute()
      if not vim.loop.fs_access(retpath, "R") then
        retpath = t.filename
      end
      return retpath
    end
  end

  local current_file_cache = {}
  return function(tag_data)
    local tag = tag_data.name
    local file = tag_data.filename
    local scode = tag_data.cmd:sub(3, -2)
    local kind = tag_data.kind
    local line = tag_data.line

    if Path.path.sep == "\\" then
      file = string.gsub(file, "/", "\\")
    end

    if opts.only_current_file then
      if current_file_cache[file] == nil then
        current_file_cache[file] = Path:new(file):normalize(cwd) == current_file
      end

      if current_file_cache[file] == false then
        return nil
      end
    end

    local tag_entry = {}
    if opts.only_sort_tags then
      tag_entry.ordinal = tag
    else
      tag_entry.ordinal = file .. ": " .. tag
    end

    tag_entry.display = make_display
    tag_entry.scode = scode
    tag_entry.tag = tag
    tag_entry.filename = file
    tag_entry.col = 1
    tag_entry.lnum = line and tonumber(line) or 1
    if show_kind then
      tag_entry.kind = kind
    end

    return setmetatable(tag_entry, mt)
  end
end

local tag_not_found_msg = { msg = "No tags found!", level = "ERROR", }

ctags_plus.jump_to_tag = function(opts)
  -- Get the word under the cursor presently
  local word = vim.fn.expand "<cword>"

  local tags = vim.fn.taglist(string.format("^%s$\\C", word))
  local size = #tags
  if size == 0 then
    utils.notify("gnfisher.ctags_plus", tag_not_found_msg)
    return
  end

  if size == 1 then
    vim.cmd.tag(word)
    return
  end

  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
 
  local finder_opt = {
    results = tags,
    entry_maker = vim.F.if_nil(opts.entry_maker, gen_from_ctags(opts)),
  }

  pickers.new(opts, {
    push_cursor_on_edit = true,
    prompt_title = "Matching Tags",
    finder = finders.new_table(finder_opt),
    previewer = previewers.ctags.new(opts),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function()
        action_set.select:enhance {
          post = function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end

            if selection.scode then
              -- un-escape / then escape required
              -- special chars for vim.fn.search()
              -- ] ~ *
              local scode = selection.scode:gsub([[\/]], "/"):gsub("[%]~*]", function(x)
                return "\\" .. x
              end)

              vim.cmd "keepjumps norm! gg"
              vim.fn.search(scode)
              vim.cmd "norm! zz"
            else
              vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
            end
          end,
        }
      return true
    end,
  })
  :find()
end

return ctags_plus

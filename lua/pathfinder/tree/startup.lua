local M = {}
local api, uv = vim.api, vim.uv
local context = require('pathfinder.tree.context')

function M.setup(explorer)
  local group = api.nvim_create_augroup('PathfinderExplorer', { clear = true })
  if not context.config.default_explorer then return end
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  local function open_directory(buf, win)
    if context.state or not api.nvim_buf_is_valid(buf) or not api.nvim_win_is_valid(win)
      or api.nvim_win_get_buf(win) ~= buf then return end
    local path = api.nvim_buf_get_name(buf)
    local stat = uv.fs_stat(path)
    if not stat or stat.type ~= 'directory' then return end
    api.nvim_set_current_win(win)
    -- Return to an ordinary empty buffer when the explorer is closed.
    api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
    explorer.open({ root = path })
  end

  api.nvim_create_autocmd('BufEnter', { group = group, callback = function(args)
    if vim.v.vim_did_enter == 0 then return end
    local win = api.nvim_get_current_win()
    vim.schedule(function() open_directory(args.buf, win) end)
  end })
  api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = function()
    local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    open_directory(buf, win)
    if not context.state and vim.fn.argc() == 0 and api.nvim_buf_get_name(buf) == ''
      and vim.bo[buf].buftype == '' and not vim.bo[buf].modified
      and api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
      explorer.open()
    end
  end })
  api.nvim_create_user_command('Explore', function(args)
    explorer.open({ root = args.args ~= '' and vim.fn.fnamemodify(args.args, ':p') or vim.fn.getcwd() })
  end, { nargs = '?', complete = 'dir', desc = 'Explore with Pathfinder', force = true })
end

return M

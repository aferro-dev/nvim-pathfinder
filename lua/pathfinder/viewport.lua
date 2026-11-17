local M = {}

-- Columns are display columns (zero based), never byte offsets.
function M.center(win, column)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return end
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zz')
    local view = vim.fn.winsaveview()
    local target = column or vim.fn.virtcol('.') - 1
    view.leftcol = math.max(0, math.floor(target - vim.api.nvim_win_get_width(win) / 2))
    vim.fn.winrestview(view)
  end)
end

function M.bind(buf, callback)
  vim.keymap.set('n', 'zz', callback or function() M.center() end,
    { buffer = buf, silent = true, desc = 'Center selection vertically and horizontally' })
end

return M

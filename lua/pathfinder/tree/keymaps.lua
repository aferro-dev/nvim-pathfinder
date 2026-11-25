local M = {}

function M.attach(buf, explorer)
  local maps = {
    j = function() explorer.vertical(1) end, k = function() explorer.vertical(-1) end,
    h = function() explorer.horizontal(-1) end, l = function() explorer.horizontal(1) end,
    ['<Down>'] = function() explorer.vertical(1) end, ['<Up>'] = function() explorer.vertical(-1) end,
    ['<Left>'] = function() explorer.horizontal(-1) end, ['<Right>'] = function() explorer.horizontal(1) end,
    ['<CR>'] = explorer.activate, ['<BS>'] = explorer.parent, ['-'] = explorer.parent,
    q = explorer.close, ['<Esc>'] = explorer.close, ['<C-p>'] = explorer.close, R = explorer.refresh,
    ['<Space>'] = function() explorer.set_expanded() end,
    zo = function() explorer.set_expanded(true) end,
    zc = function() explorer.set_expanded(false) end,
    zR = explorer.expand_all, zM = explorer.collapse_all, zz = explorer.center,
    a = explorer.create, r = explorer.rename, d = explorer.delete, I = explorer.toggle_gitignore,
    D = explorer.database, p = explorer.toggle_preview,
    ['<C-A-P>'] = explorer.search, ['/'] = explorer.search,
    n = function() require('pathfinder.tree.search').next(1) end,
    N = function() require('pathfinder.tree.search').next(-1) end,

  }
  local descriptions = {
    j = 'Next node at same depth (wrap)', k = 'Previous node at same depth (wrap)', h = 'Previous nesting level (wrap)', l = 'Next nesting level (wrap)',
    ['<Down>'] = 'Next node at same depth (wrap)', ['<Up>'] = 'Previous node at same depth (wrap)',
    ['<Left>'] = 'Previous nesting level (wrap)', ['<Right>'] = 'Next nesting level (wrap)',
    ['<CR>'] = 'Open file or toggle directory', ['<Space>'] = 'Toggle directory',
    ['<BS>'] = 'Select parent', ['-'] = 'Select parent',
    q = 'Close Pathfinder', ['<Esc>'] = 'Close Pathfinder', ['<C-p>'] = 'Close Pathfinder',
    R = 'Refresh tree', zo = 'Expand node', zc = 'Collapse node',
    zR = 'Expand all nodes', zM = 'Collapse all nodes', zz = 'Center selected node',
    a = 'Create file or directory', r = 'Rename file or directory', d = 'Delete file or directory', I = 'Toggle Git-ignored files',
    D = 'Switch to database UML', p = 'Toggle file preview',
    ['<C-A-P>'] = 'Find in Pathfinder', ['/'] = 'Find in Pathfinder',
    n = 'Next search match', N = 'Previous search match',
  }
  for key, action in pairs(maps) do
    vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true, desc = descriptions[key] })
  end
end

return M

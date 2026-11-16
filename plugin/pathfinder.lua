if vim.g.loaded_pathfinder then return end
vim.g.loaded_pathfinder = true
require('pathfinder').setup()
vim.api.nvim_create_user_command('Pathfinder', function(opts)
  require('pathfinder').open({ root = opts.args ~= '' and vim.fn.fnamemodify(opts.args, ':p') or nil })
end, { nargs = '?', complete = 'dir', desc = 'Full-screen repository explorer' })

vim.api.nvim_create_user_command('PathfinderDatabase', function()
  require('pathfinder').database()
end, { desc = 'Database schema and data (SQLite / PostgreSQL / MongoDB)' })

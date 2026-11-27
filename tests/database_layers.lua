vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local explorer, db = require('pathfinder'), require('pathfinder.database')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({ 'example' }, root .. '/example.txt')
vim.o.winblend = 45
local function key(name, mode) vim.fn.maparg(name, mode or 'n', false, true).callback() end
local function text() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
explorer.open({ root = root })
local tree = api.nvim_get_current_win()
local tree_buf = api.nvim_get_current_buf()
key('D')
local input = api.nvim_get_current_win()
key('<Esc>', 'i')
local diagram = api.nvim_get_current_win()
assert(api.nvim_win_get_config(tree).hide)
assert(vim.wo[diagram].winblend == 0)
assert(vim.wo[diagram].winhighlight:find('Normal:PathfinderDialog', 1, true))
key('a')
assert(api.nvim_get_current_win() == diagram) -- a cannot create a connection outside the manager
key('c')
local manager = api.nvim_get_current_win()
assert(vim.wo[manager].winblend == 0 and vim.wo[manager].winbar == '')
assert(vim.wo[manager].winhighlight:find('Normal:PathfinderDialog', 1, true))
key('a')
assert(api.nvim_get_current_win() ~= manager)
assert(not api.nvim_win_is_valid(manager)) -- a switches modals, without stacking them
key('<Esc>', 'i')
assert(api.nvim_get_current_win() == diagram)
-- Mock only the remote Redis process; exercise actual windows and mappings.
local original_system = vim.system
vim.system = function(command, _, callback)
  assert(command[1] == 'python3')
  local result = command[3] == 'schema' and { { name = 'Keys', columns = { { name = 'key', type = 'bytes', pk = true } }, foreign_keys = {} } }
    or { { key = 'example', type = 'string', ttl = -1, size = 5, value = 'hello', truncated = false } }
  vim.schedule(function() callback({ code = 0, stdout = vim.json.encode(result) }) end)
  return { kill = function() end }
end
key('c')
key('a')
api.nvim_buf_set_lines(0, 0, -1, false, { 'redis://localhost:6379/0' })
key('<CR>', 'i')
assert(vim.wait(1000, function() return vim.bo.filetype == 'pathfinder_database_data' and text():find('hello', 1, true) end))
local grid = api.nvim_get_current_win()
assert(api.nvim_win_get_config(tree).hide and api.nvim_win_get_config(diagram).hide)
assert(vim.wo[grid].winblend == 0)
local original_input = vim.ui.input
local prompt
vim.ui.input = function(opts, callback) prompt = opts.prompt; callback(nil) end
key('a')
assert(prompt:find('New Redis string key', 1, true))
assert(api.nvim_get_current_win() == grid)
vim.ui.input = original_input
key('c')
assert(not api.nvim_win_is_valid(grid))
assert(not api.nvim_win_get_config(diagram).hide)
key('<Esc>')
assert(vim.wait(1000, function() return vim.bo.filetype == 'pathfinder_database_data' end))
key('q')
assert(api.nvim_get_current_win() == tree)
assert(not api.nvim_win_get_config(tree).hide)
assert(api.nvim_get_current_buf() == tree_buf)
prompt = nil
vim.ui.input = function(opts, callback) prompt = opts.prompt; callback(nil) end
key('a')
assert(prompt:find('Create in', 1, true)) -- tree a retains file creation
vim.ui.input, vim.system = original_input, original_system
explorer.close()
vim.fn.delete(root, 'rf')
print('Database layers: scoped a, opaque windows, hidden parents, modal replacement and tree restoration passed')
vim.cmd('qa!')

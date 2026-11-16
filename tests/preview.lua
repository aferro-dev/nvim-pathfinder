vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local p = require('pathfinder')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({ 'local value = 42', 'return value' }, root .. '/a.lua')
local fd = assert(vim.uv.fs_open(root .. '/b.bin', 'w', 420))
vim.uv.fs_write(fd, 'binary\0data', 0)
vim.uv.fs_close(fd)
vim.fn.mkdir(root .. '/directory')
p.open({ root = root })
local tree = api.nvim_get_current_win()
local full_width = api.nvim_win_get_width(tree)
assert(vim.fn.maparg('p', 'n', false, true).desc == 'Toggle file preview')
p.vertical(1) -- directories sort first; select a.lua
p.toggle_preview()
assert(api.nvim_get_current_win() == tree)
assert(api.nvim_win_get_width(tree) < full_width)
local preview
for _, win in ipairs(api.nvim_list_wins()) do
  if api.nvim_win_get_config(win).zindex == 51 then preview = win end
end
assert(preview)
local buf = api.nvim_win_get_buf(preview)
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'local value = 42')
assert(vim.bo[buf].filetype == 'lua' and not vim.bo[buf].modifiable)
p.vertical(1)
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'Binary file')
local source = vim.fn.bufadd(root .. '/a.lua')
vim.fn.bufload(source)
api.nvim_buf_set_lines(source, 0, -1, false, { 'unsaved text' })
p.vertical(-1)
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'unsaved text')
vim.o.columns = 45
vim.o.lines = 15
vim.cmd('doautocmd VimResized')
assert(api.nvim_win_get_config(preview).col + api.nvim_win_get_width(preview) == 45)
p.toggle_preview()
assert(not api.nvim_win_is_valid(preview) and not api.nvim_buf_is_valid(buf))
assert(api.nvim_win_get_width(tree) == 45)
p.toggle_preview()
local windows = #api.nvim_list_wins()
p.close()
assert(#api.nvim_list_wins() == windows - 2)
assert(api.nvim_buf_get_lines(source, 0, 1, false)[1] == 'unsaved text')
vim.bo[source].modified = false
vim.fn.delete(root, 'rf')
print('File preview passed')
vim.cmd('qa!')

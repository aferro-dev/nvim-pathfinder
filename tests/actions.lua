vim.opt.runtimepath:prepend(vim.fn.getcwd())
local p = require('pathfinder')
local temp = vim.fn.tempname()
local root = temp .. '/project'
vim.fn.mkdir(root, 'p')
local input, confirm, notify = vim.ui.input, vim.fn.confirm, vim.notify
local answer, choice, errors = nil, nil, {}
vim.ui.input = function(_, cb) cb(answer) end
vim.fn.confirm = function(_, buttons, default)
  assert(buttons == '&Yes\n&No' and default == 2)
  return choice
end
vim.notify = function(message) errors[#errors + 1] = message end
p.open({ root = root })
answer = 'nested/file with spaces.lua'; p.create()
local file = root .. '/nested/file with spaces.lua'
assert(vim.uv.fs_stat(file))
assert(vim.api.nvim_get_current_line():find('file with spaces.lua', 1, true))
answer = 'file with spaces.lua'; p.create()
assert(errors[#errors]:find('Already exists', 1, true))
answer = '../escape.lua'; p.create()
assert(not vim.uv.fs_stat(root .. '/escape.lua'))
answer = nil; p.create() -- cancelled input
choice = 2; p.delete()
assert(vim.uv.fs_stat(file))
local buf = vim.fn.bufadd(file)
vim.fn.bufload(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'unsaved work' })
choice = 1; p.delete()
assert(vim.uv.fs_stat(file) and vim.bo[buf].modified)
p.parent(); p.delete() -- recursive delete also protects dirty descendants
assert(vim.uv.fs_stat(file))
vim.bo[buf].modified = false
p.delete()
assert(not vim.uv.fs_stat(root .. '/nested'))
assert(not vim.api.nvim_buf_is_valid(buf))
answer = 'empty/'; p.create()
assert(vim.uv.fs_stat(root .. '/empty').type == 'directory')
p.delete()
assert(not vim.uv.fs_stat(root .. '/empty'))
-- Removing a directory symlink never deletes its destination.
vim.fn.mkdir(temp .. '/outside', 'p')
vim.fn.writefile({ 'keep' }, temp .. '/outside/keep.txt')
assert(vim.uv.fs_symlink(temp .. '/outside', root .. '/link', { dir = true }))
p.refresh(); p.delete()
assert(not vim.uv.fs_lstat(root .. '/link'))
assert(vim.uv.fs_stat(temp .. '/outside/keep.txt'))
-- Reject creation through a symlink that escapes the selected directory.
assert(vim.uv.fs_symlink(temp .. '/outside', root .. '/link', { dir = true }))
p.close(); p.open({ root = root }); p.parent()
-- Select root by reopening the now empty project after removing the link.
vim.uv.fs_unlink(root .. '/link')
p.refresh()
assert(vim.uv.fs_symlink(temp .. '/outside', root .. '/link', { dir = true }))
answer = 'link/escape.lua'; p.create()
assert(not vim.uv.fs_stat(temp .. '/outside/escape.lua'))
assert(vim.fn.maparg('a', 'n', false, true).desc == 'Create file or directory')
assert(vim.fn.maparg('d', 'n', false, true).desc == 'Delete file or directory')
local pending
vim.ui.input = function(_, cb) pending = cb end
p.create(); p.close(); pending('late.lua')
assert(not vim.uv.fs_stat(root .. '/late.lua'))
vim.ui.input, vim.fn.confirm, vim.notify = input, confirm, notify
vim.fn.delete(temp, 'rf')
print('File actions passed')
vim.cmd('qa!')

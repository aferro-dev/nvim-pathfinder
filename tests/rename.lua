vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
local p = require('pathfinder')
local api, uv = vim.api, vim.uv
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local input, notify = vim.ui.input, vim.notify
local answer, errors = nil, {}
vim.ui.input = function(opts, cb)
  if opts.prompt == 'Rename: ' then assert(opts.default and opts.default ~= '') end
  cb(answer)
end
vim.notify = function(message) errors[#errors + 1] = message end
p.open({ root = root })
answer = 'old.txt'; p.create()
local buf = vim.fn.bufadd(root .. '/old.txt')
vim.fn.bufload(buf)
api.nvim_buf_set_lines(buf, 0, -1, false, { 'unsaved work' })
answer = 'new name.txt'; p.rename()
assert(not uv.fs_lstat(root .. '/old.txt') and uv.fs_stat(root .. '/new name.txt'))
assert(api.nvim_buf_get_name(buf) == root .. '/new name.txt')
assert(vim.bo[buf].modified and api.nvim_buf_get_lines(buf, 0, -1, false)[1] == 'unsaved work')
assert(api.nvim_get_current_line():find('new name.txt', 1, true))
assert(vim.fn.maparg('r', 'n', false, true).desc == 'Rename file or directory')
vim.fn.writefile({}, root .. '/exists.txt')
answer = 'exists.txt'; p.rename()
assert(errors[#errors]:find('Already exists', 1, true))
for _, invalid in ipairs({ '../escape', '.', '..', '/absolute', 'bad\nname' }) do
  answer = invalid; p.rename()
  assert(uv.fs_stat(root .. '/new name.txt'))
end
answer = nil; p.rename()
answer = 'new name.txt'; p.rename()
assert(uv.fs_stat(root .. '/new name.txt'))
-- Renaming a directory updates dirty descendants without saving them.
answer = 'nested/deep/file.txt'; p.create()
local child = vim.fn.bufadd(root .. '/nested/deep/file.txt')
vim.fn.bufload(child)
api.nvim_buf_set_lines(child, 0, -1, false, { 'dirty descendant' })
p.parent(); p.parent()
answer = 'renamed'; p.rename()
assert(uv.fs_stat(root .. '/renamed/deep/file.txt'))
assert(api.nvim_buf_get_name(child) == root .. '/renamed/deep/file.txt' and vim.bo[child].modified)
assert(not uv.fs_lstat(root .. '/nested'))
-- A destination buffer also prevents renaming, even without a disk file.
local collision = vim.fn.bufadd(root .. '/occupied/deep/file.txt')
answer = 'occupied'; p.rename()
assert(errors[#errors]:find('A buffer already exists', 1, true))
assert(uv.fs_stat(root .. '/renamed/deep/file.txt'))
api.nvim_buf_delete(collision, { force = true })
-- A delayed prompt cannot rename entries after its explorer was closed.
local pending
vim.ui.input = function(_, cb) pending = cb end
p.rename(); p.close(); pending('late')
assert(uv.fs_stat(root .. '/renamed/deep/file.txt') and not uv.fs_lstat(root .. '/late'))
vim.ui.input, vim.notify = input, notify
vim.fn.delete(root, 'rf')
print('Pathfinder rename passed')
vim.cmd('qa!')

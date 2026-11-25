vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
local p = require('pathfinder')
local context = require('pathfinder.tree.context')
local model = require('pathfinder.tree.model')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/nested', 'p')
vim.fn.writefile({}, root .. '/nested/keep.txt')
vim.cmd.edit(root .. '/nested/keep.txt')
p.open({ root = root })
local session = context.state
local function external(code)
  local result = vim.system({ 'python3', '-c', 'from pathlib import Path; import sys; r = Path(sys.argv[1]); ' .. code, root }):wait()
  assert(result.code == 0, result.stderr)
end
local function eventually(check)
  assert(vim.wait(3000, check, 20), 'External change was not reflected')
end
external("(r / 'new.txt').touch(); (r / 'newdir').mkdir(); (r / 'nested/new.txt').touch()")
eventually(function()
  return session.nodes[root .. '/new.txt'] and session.nodes[root .. '/newdir']
    and session.nodes[root .. '/nested/new.txt']
end)
assert(model.current().path == root .. '/nested/keep.txt')
assert(session.nodes[root .. '/nested'].open)
external("(r / 'nested/new.txt').rename(r / 'nested/renamed.txt'); (r / 'new.txt').unlink()")
eventually(function()
  return session.nodes[root .. '/nested/renamed.txt'] and not session.nodes[root .. '/nested/new.txt']
    and not session.nodes[root .. '/new.txt']
end)
-- A deleted selection falls back to a surviving parent.
external("(r / 'nested/keep.txt').unlink()")
eventually(function() return not session.nodes[root .. '/nested/keep.txt'] end)
assert(model.current().path == root .. '/nested')
-- Search results must include externally created matching paths.
require('pathfinder.tree.search').update('match')
external("(r / 'newdir/match.txt').touch()")
eventually(function() return session.nodes[root .. '/newdir/match.txt'] end)
assert(#session.search_matches == 1)
-- Focus refresh also covers filesystems where watch events are unavailable.
external("(r / 'focus.txt').touch()")
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(session.nodes[root .. '/focus.txt'])
local watch = session.watch
p.close()
assert(not session.watch and watch.timer:is_closing())
for _, handle in pairs(watch.handles) do assert(handle:is_closing()) end
p.open({ root = root })
local reopened = context.state
vim.wait(200, function() return false end)
assert(context.state == reopened)
p.close()
vim.fn.delete(root, 'rf')
print('Pathfinder external refresh passed')
vim.cmd('qa!')

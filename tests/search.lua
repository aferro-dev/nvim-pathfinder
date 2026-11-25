vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false
local p = require('pathfinder')
local search = require('pathfinder.tree.search')
local context = require('pathfinder.tree.context')
local api = vim.api
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/src/deep', 'p')
vim.fn.mkdir(root .. '/vendor', 'p')
vim.fn.writefile({ 'vendor/' }, root .. '/.gitignore')
vim.fn.writefile({ 'first', 'second', 'third' }, root .. '/src/deep/Match.lua')
vim.fn.writefile({}, root .. '/src/match.txt')
vim.fn.writefile({}, root .. '/vendor/match.txt')
assert(vim.system({ 'git', '-C', root, 'init', '-q' }):wait().code == 0)
vim.uv.fs_symlink(root, root .. '/src/loop')
vim.cmd.enew()
local origin = api.nvim_get_current_win()
vim.o.winbar = 'Editor bar'
vim.wo.number = true
local highlights = vim.wo.winhighlight
p.open({ root = root })
assert(search.update('MATCH') == 2)
local s = context.state
assert(s.nodes[root .. '/src/deep/Match.lua'])
assert(not s.nodes[root .. '/vendor'])
assert(require('pathfinder.tree.model').current().name == 'Match.lua')
local marks = api.nvim_buf_get_extmarks(s.buf, api.nvim_create_namespace('pathfinder'), 0, -1, { details = true })
local highlighted = false
for _, mark in ipairs(marks) do
  if mark[4].hl_group == 'PathfinderSearch' then highlighted = true end
end
assert(highlighted)
search.next(1)
assert(require('pathfinder.tree.model').current().name == 'match.txt')
search.next(1)
assert(require('pathfinder.tree.model').current().name == 'Match.lua')
search.next(-1)
assert(require('pathfinder.tree.model').current().name == 'match.txt')
assert(search.update('deep') == 1)
assert(s.nodes[root .. '/src/deep'])
assert(search.update('missing') == 0)
search.update('')
assert(not s.nodes[root .. '/src/deep'])
-- Exercise the actual prompt and live CmdlineChanged callback.
local live_query, live_node
vim.keymap.set('c', '<F6>', function()
  live_query = s.search_query
  live_node = s.nodes[root .. '/src/deep/Match.lua']
  return ''
end, { expr = true })
api.nvim_feedkeys('match' .. api.nvim_replace_termcodes('<F6><CR>', true, false, true), 't', false)
p.search()
vim.keymap.del('c', '<F6>')
assert(live_query == 'match' and live_node, 'Tree must update before Enter')
assert(s.search_query == 'match' and #s.search_matches == 2)
p.activate()
assert(api.nvim_get_current_win() == origin)
assert(api.nvim_buf_get_name(0) == root .. '/src/deep/Match.lua')
assert(vim.wo.winbar == 'Editor bar' and vim.wo.number and vim.wo.winhighlight == highlights,
  vim.inspect({ bar = vim.wo.winbar, number = vim.wo.number, hl = vim.wo.winhighlight }))
-- External pickers use :edit in the originating explorer window.
p.open({ root = root })
p.toggle_preview()
vim.cmd.edit(root .. '/src/deep/Match.lua')
api.nvim_win_set_cursor(0, { 2, 2 })
assert(vim.wait(1000, function() return context.state == nil end))
assert(api.nvim_get_current_win() == origin)
assert(vim.deep_equal(api.nvim_win_get_cursor(0), { 2, 2 }))
assert(#api.nvim_list_wins() == 1)
assert(vim.wo.winbar == 'Editor bar' and vim.wo.number and vim.wo.winhighlight == highlights)
vim.fn.delete(root, 'rf')
print('Pathfinder search passed')
vim.cmd('qa!')

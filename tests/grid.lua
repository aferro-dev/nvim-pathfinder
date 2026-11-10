vim.opt.runtimepath:prepend(vim.fn.getcwd())
local p = require('pathfinder')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/apps/backend/scripts', 'p')
vim.fn.mkdir(root .. '/apps/backend/src/app', 'p')
vim.fn.mkdir(root .. '/apps/web', 'p')
for _, name in ipairs({ 'seed-entries.ts', 'seed-food.ts', 'seed-preparations.ts' }) do
  vim.fn.writefile({}, root .. '/apps/backend/scripts/' .. name)
end
vim.fn.writefile({}, root .. '/apps/backend/src/index.ts')
vim.cmd.edit(root .. '/apps/backend/scripts/seed-food.ts')
p.open({ root = root })
local function has(name)
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line():sub(col + 1)
  assert(line:find(name, 1, true), line .. ' expected ' .. name)
end
local function contents() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
has('seed-food.ts')
assert(not contents():find('index.ts', 1, true)) -- src starts collapsed
local original_col = vim.api.nvim_win_get_cursor(0)[2]
p.parent(); has('scripts/')
assert(vim.api.nvim_win_get_cursor(0)[2] < original_col)
p.vertical(1); has('src/')
p.set_expanded(true); has('app/')
p.parent(); has('src/')
local map = contents()
-- On a roomy terminal, both axes center the map rather than pinning it top-left.
vim.o.columns = 180
vim.o.lines = 60
vim.api.nvim_exec_autocmds('VimResized', {})
local centered = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local first_content
for i, line in ipairs(centered) do
  if line:find('%S') then first_content = i; assert(line:match('^    ')); break end
end
assert(first_content and first_content > 1)
assert(vim.wo.winbar:find('pathfinder', 1, true))
assert(not vim.wo.winbar:find('Explorer', 1, true))

assert(map:find('index.ts', 1, true))
for _, name in ipairs({ 'scripts/', 'src/', 'app/', 'seed-food.ts' }) do
  local _, count = map:gsub(vim.pesc(name), '')
  assert(count == 1, name .. ' duplicated')
end
p.activate(); has('src/') -- close through Enter
assert(not contents():find('index.ts', 1, true))
p.activate(); has('app/')
p.vertical(-1); has('seed-preparations.ts') -- same depth, different parent
p.vertical(-1); has('seed-food.ts')
p.vertical(-1); has('seed-entries.ts')
p.parent(); has('scripts/')
p.set_expanded(false)
assert(not contents():find('seed-', 1, true))
p.set_expanded(true); has('seed-entries.ts')
p.parent(); has('scripts/')
assert(contents():find('seed-food.ts', 1, true))
p.refresh(); has('scripts/')
assert(contents():find('seed-food.ts', 1, true))
p.set_expanded(false)
p.refresh()
assert(not contents():find('seed-food.ts', 1, true))
-- Refresh handles removed selection without leaving stale cursor geometry.
vim.fn.delete(root .. '/apps/backend/scripts', 'rf')
p.refresh()
p.close()
-- Down from nixvim.nix opens plugin and selects its child automatically.
local navigation = root .. '/navigation'
for _, name in ipairs({ 'nix', 'plugin', 'tests', 'z-empty' }) do vim.fn.mkdir(navigation .. '/' .. name, 'p') end
for _, name in ipairs({ 'nix/nixvim.nix', 'plugin/pathfinder.lua', 'tests/grid.lua', 'README.md' }) do
  vim.fn.writefile({}, navigation .. '/' .. name)
end
vim.cmd.edit(navigation .. '/nix/nixvim.nix')
p.open({ root = navigation })
local depth_col = vim.api.nvim_win_get_cursor(0)[2]
p.vertical(1); has('pathfinder.lua')
p.parent(); has('plugin/')
p.horizontal(1); has('pathfinder.lua')
p.vertical(1); has('grid.lua')
p.vertical(1); has('z-empty/')
assert(vim.api.nvim_win_get_cursor(0)[2] < depth_col)
p.vertical(1); has('README.md')
p.close()
-- The same behavior applies upwards into an initially collapsed branch.
vim.cmd.edit(navigation .. '/plugin/pathfinder.lua')
p.open({ root = navigation })
assert(not contents():find('nixvim.nix', 1, true))
p.vertical(-1); has('nixvim.nix')
p.close()
-- Bulk actions traverse closed descendants, preserve selection, and honor filters.
vim.fn.mkdir(navigation .. '/plugin/nested/deeper', 'p')
vim.fn.writefile({}, navigation .. '/plugin/nested/deeper/leaf.lua')
vim.fn.mkdir(navigation .. '/.git/hidden', 'p')
vim.fn.writefile({}, navigation .. '/.git/hidden/secret.txt')
vim.uv.fs_symlink(navigation, navigation .. '/plugin/cycle', { dir = true })
vim.cmd.edit(navigation .. '/plugin/pathfinder.lua')
p.open({ root = navigation })
p.expand_all(); has('pathfinder.lua')
assert(contents():find('leaf.lua', 1, true))
assert(not contents():find('secret.txt', 1, true))
p.collapse_all(); has('plugin/')
assert(not contents():find('pathfinder.lua', 1, true))
p.set_expanded(true); has('nested/')
assert(not contents():find('leaf.lua', 1, true)) -- hidden descendants were collapsed too
p.expand_all(); has('nested/')
assert(contents():find('leaf.lua', 1, true))
assert(vim.fn.maparg('zR', 'n', false, true).desc == 'Expand all nodes')
assert(vim.fn.maparg('zM', 'n', false, true).desc == 'Collapse all nodes')
local footer = vim.api.nvim_win_get_config(0).footer
local labels = {}
for _, chunk in ipairs(footer) do labels[#labels + 1] = chunk[1] end
assert(table.concat(labels):find('expand/collapse all', 1, true))
p.close()
-- Offscreen nodes must not retain clickable cursor positions after scrolling.
for i = 1, 80 do vim.fn.writefile({}, root .. '/' .. string.format('%03d.txt', i)) end
vim.cmd.edit(root .. '/080.txt')
p.open({ root = root })
has('080.txt')
p.vertical(-1); has('079.txt')
for _ = 1, 60 do p.vertical(-1) end
has('019.txt')
p.vertical(1); has('020.txt')
p.close()
vim.fn.delete(root, 'rf')
print('Tree map navigation passed')
vim.cmd('qa!')

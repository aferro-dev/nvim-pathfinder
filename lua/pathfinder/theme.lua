local M = {}

-- Link to the user's highlights; only rounded caps need derived colors.
function M.apply()
  local links = {
    PathfinderNormal = 'Normal',
    PathfinderDirectory = 'Directory',
    PathfinderAncestor = 'CursorLine',
    PathfinderSelected = 'Visual',
    PathfinderBadge = 'Title',
    PathfinderConnector = 'NonText',
    PathfinderBorder = 'WinSeparator',
    PathfinderMuted = 'Comment',
    PathfinderKey = 'Special',
  }
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = target })
  end
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local canvas = vim.api.nvim_get_hl(0, { name = 'PathfinderNormal', link = false })
  for name, surface in pairs({
    PathfinderDirectoryEdge = 'PathfinderDirectory',
    PathfinderAncestorEdge = 'PathfinderAncestor',
    PathfinderSelectedEdge = 'PathfinderSelected',
    PathfinderKeyEdge = 'PathfinderKey',
  }) do
    local hl = vim.api.nvim_get_hl(0, { name = surface, link = false })
    vim.api.nvim_set_hl(0, name, {
      fg = hl.bg or canvas.bg or normal.bg,
      bg = canvas.bg or normal.bg,
      ctermfg = hl.ctermbg or canvas.ctermbg or normal.ctermbg,
      ctermbg = canvas.ctermbg or normal.ctermbg,
    })
  end
end

function M.setup()
  M.apply()
  local group = vim.api.nvim_create_augroup('PathfinderTheme', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply })
end

return M

local M = {}

-- Link to the user's highlights; only rounded caps need derived colors.
function M.apply()
  local links = {
    PathfinderNormal = 'NormalFloat',
    PathfinderDirectory = 'Pmenu',
    PathfinderAncestor = 'CursorLine',
    PathfinderSelected = 'PmenuSel',
    PathfinderBadge = 'PmenuSel',
    PathfinderConnector = 'NonText',
    PathfinderBorder = 'FloatBorder',
    PathfinderMuted = 'Comment',
    PathfinderKey = 'StatusLine',
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

return M

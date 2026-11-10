local M = {}

-- A quiet, self-contained palette: never change the editor's colorscheme.
function M.apply()
  local bg = '#101019'
  local groups = {
    PathfinderNormal = { fg = '#dedce9', bg = bg },
    PathfinderDirectory = { fg = '#d3d1e4', bg = '#1b1b2b' },
    PathfinderAncestor = { fg = '#eeebfa', bg = '#303047' },
    PathfinderSelected = { fg = '#211a32', bg = '#bba3eb', bold = true },
    PathfinderDirectoryEdge = { fg = '#1b1b2b', bg = bg },
    PathfinderAncestorEdge = { fg = '#303047', bg = bg },
    PathfinderSelectedEdge = { fg = '#bba3eb', bg = bg },
    PathfinderBadge = { fg = '#211a32', bg = '#bba3eb', bold = true },
    PathfinderConnector = { fg = '#9280b9', bg = bg },
    PathfinderBorder = { fg = '#65557f', bg = bg },
    PathfinderKey = { fg = '#cfcae4', bg = '#262438' },
    PathfinderKeyEdge = { fg = '#262438', bg = bg },
    PathfinderMuted = { fg = '#9c96b8', bg = bg },
    PathfinderFolderIcon = { fg = '#8fb9ed' },
    PathfinderFileIcon = { fg = '#a6a2bb' },
    PathfinderSelectedIcon = { fg = '#302143', bg = '#bba3eb' },
  }
  for name, definition in pairs(groups) do vim.api.nvim_set_hl(0, name, definition) end
end

return M

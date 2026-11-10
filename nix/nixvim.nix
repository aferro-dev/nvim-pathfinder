{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins = [ (import ../default.nix { inherit pkgs; }) ];
    extraConfigLua = ''require("pathfinder").setup({})'';
    keymaps = [{
      mode = "n";
      key = "<C-p>";
      action = "<cmd>Pathfinder<CR>";
      options = { silent = true; desc = "Explore repository"; };
    }];
  };
}

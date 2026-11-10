{ pkgs }:
pkgs.vimUtils.buildVimPlugin {
  pname = "nvim-pathfinder";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ./.;
  meta = {
    description = "Full-screen hierarchical repository explorer for Neovim";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.all;
  };
}

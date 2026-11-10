{
  description = "Full-screen hierarchical Neovim explorer";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in {
      packages = eachSystem (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
        default = import ./default.nix { inherit pkgs; };
      });
      homeManagerModules.default = import ./nix/nixvim.nix;
    };
}

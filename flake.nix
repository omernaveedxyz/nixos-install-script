{
  inputs = {
    # Externally extensible flake systems
    systems.url = "github:nix-systems/x86_64-linux";

    # Nix Packages collection & NixOS
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pure Nix flake utility functions
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    inherit (nixpkgs.lib) genAttrs;
    inherit (flake-utils.lib) defaultSystems;

    # Create attribute set of default systems from flake-utils
    genAttrsFromDefaultSystems = genAttrs defaultSystems;

    # Extended Nixpkgs collection with additional and modified packages
    legacyPackages = genAttrsFromDefaultSystems (system:
      import nixpkgs {
        inherit system;
        overlays = [(final: prev: {nixos-install-script = final.callPackage ./package.nix {};})];
      });
  in {
    # `nix build` - Build the package alongside its dependencies
    packages = genAttrsFromDefaultSystems (system: {default = legacyPackages.${system}.nixos-install-script;});

    # `nix build -L .#checks.<system>.<name>` - Run integration tests on NixOS virtual machines
    checks = genAttrsFromDefaultSystems (system: import ./tests {pkgs = legacyPackages.${system};});

    # `nix fmt` - Reformat your code in the standard style
    formatter = genAttrsFromDefaultSystems (system: legacyPackages.${system}.alejandra);
  };
}

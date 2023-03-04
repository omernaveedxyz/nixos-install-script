{
  description = "nixos configuration";

  # specify code's dependencies in a declarative way
  inputs = {
    # nix package collection
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # pure nix flake utility functions
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let

        pkgs = import nixpkgs { inherit system; };

      in
      {
        # configuration to build the package.
        # accessible through 'nix build'
        defaultPackage = with pkgs;
          let

            script = import ./script.nix { inherit pkgs; };
            inherit (script) installationScript;

          in
          stdenv.mkDerivation {
            # the package name
            pname = "nixos-install-script";

            # the package version
            version = "1.3.0";

            # the package source directory
            src = self;

            # a shell script to run during the install phase
            installPhase = ''
              mkdir -p $out/bin
              cp ${installationScript}/bin/installationScript $out/bin
              chmod +x $out/bin/installationScript
            '';
          };

        # initiate development environment using nix develop
        # accessible through 'nix develop' or 'nix-shell' (legacy)
        devShells = import ./shell.nix { inherit pkgs; };
      });
}

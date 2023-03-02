{

  # Specify code's dependencies in a declarative way.
  inputs = {
    # Nix package collection
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux = with import nixpkgs { system = "x86_64-linux"; };
      let
        script = import ./script.nix { inherit pkgs; };
        inherit (script) installationScript;
      in
      stdenv.mkDerivation {
        # The package name.
        pname = "nixos-install-script";

        # The package version.
        version = "1.1.1";

        # The package source directory.
        src = self;

        # A shell script to run during the install phase.
        installPhase = ''
          mkdir -p $out/bin
          cp ${installationScript}/bin/installationScript $out/bin
          chmod +x $out/bin/installationScript
        '';
      };
  };

}

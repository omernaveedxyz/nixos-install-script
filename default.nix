{ pkgs ? import <nixpkgs> { } }: {

  output =
    let

      script = import ./script.nix { inherit pkgs; };
      inherit (script) installationScript;

    in
    pkgs.stdenv.mkDerivation {
      # The package name.
      pname = "nixos-install-script";

      # The package version.
      version = "1.0.1";

      # The package source directory.
      src = ./.;

      # A shell script to run during the install phase.
      installPhase = ''
        mkdir -p $out/bin
        cp ${installationScript}/bin/installationScript $out/bin
        chmod +x $out/bin/installationScript
      '';
    };

  # Series of tests that can be run using `nix-build -A tests.<name>`
  tests = {
    default = pkgs.nixosTest ./tests/default.nix;
    hibernate = pkgs.nixosTest ./tests/hibernate.nix;
    luks = pkgs.nixosTest ./tests/luks.nix;
    luks2 = pkgs.nixosTest ./tests/luks2.nix;
    fido = pkgs.nixosTest ./tests/fido.nix;
    fido2 = pkgs.nixosTest ./tests/fido2.nix;
  };

}

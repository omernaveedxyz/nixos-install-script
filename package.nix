{
  lib,
  pkgs,
  stdenv,
  ...
}: let
  inherit (lib) makeBinPath;
in
  stdenv.mkDerivation rec {
    # The derivation name
    name = "nixos-install-script";

    # The package source directory
    src = ./src;

    # A shell script to run during the install phase
    installPhase = ''
      install -Dm755 nixos-install-script.sh $out/bin/nixos-install-script
    '';
  }

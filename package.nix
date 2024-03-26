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

    # The package's build-time dependencies
    nativeBuildInputs = with pkgs; [makeWrapper];

    # The package's run-time dependencies
    buildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      util-linux
      systemd
      gptfdisk
      gawk
      dosfstools
      btrfs-progs
      cryptsetup
      nixos-install-tools
      gnused
    ];

    # A shell script to run during the install phase
    installPhase = ''
      install -Dm755 nixos-install-script.sh $out/bin/nixos-install-script
      wrapProgram $out/bin/nixos-install-script --prefix PATH : '${makeBinPath buildInputs}'
    '';
  }

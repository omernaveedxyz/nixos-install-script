{ lib, pkgs, system ? builtins.currentSystem, ... }:

let

  helpers = import ./helpers { inherit lib pkgs system installedConfig; };
  inherit (helpers) install-script createNamedMachine createFailTestCase installConfiguration
    hostnameFailTestCases driveFailTestCases fidoFailTestCases2;

  # Configuration of client machine afer installation.
  installedConfig = {
    imports = [ (import ./helpers/clientConfig.nix { hostName = "fido"; }) ];

    boot.initrd.luks.devices."fido".device = "/dev/disk/by-label/fido-luks";
    boot.initrd.luks.devices."fido".crypttabExtraOpts = [ "fido2-device=auto" ];
  };

in
{
  name = "FIDO Configuration Test p.2";

  # Configuration of machine for install.
  nodes.machine = {
    imports = [ (import ./helpers/machineConfig.nix { inherit lib; }) ];

    virtualisation.qemu.package = lib.mkForce (pkgs.qemu_test.override { canokeySupport = true; });
    virtualisation.qemu.options = [ "-device canokey,file=/tmp/canokey-file" ];
  };

  # Script that will be run for this particular test.
  testScript = ''
    ${createNamedMachine}
    ${createFailTestCase}
    ${installConfiguration}

    machine.start()

    ${hostnameFailTestCases}
    ${driveFailTestCases}
    ${fidoFailTestCases2}

    # Install configuration onto machine.
    install_configuration("echo y | ${install-script}/bin/install.sh --hostname=fido --enable-luks --enable-fido2=/dev/hidraw1 /dev/vda")
    result = machine.succeed("cat fido-recovery.txt").strip()
    machine.shutdown()

    # Verify that client boots.
    client = create_named_machine("client")
    client.start()
    client.wait_for_console_text("Starting password query on")
    client.send_console(result + "\n")
    client.wait_for_unit("multi-user.target")
  '';
}

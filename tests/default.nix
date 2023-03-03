{ lib, pkgs, system ? builtins.currentSystem, ... }:

let

  helpers = import ./helpers { inherit lib pkgs system installedConfig; };
  inherit (helpers) install-script createNamedMachine createFailTestCase installConfiguration
    hostnameFailTestCases driveFailTestCases;

  # configuration of client machine afer installation
  installedConfig = {
    imports = [ (import ./helpers/clientConfig.nix { hostName = "root"; }) ];
  };

in
{
  name = "Default Configuration Test";

  # configuration of machine for install
  nodes.machine = {
    imports = [ (import ./helpers/machineConfig.nix { inherit lib; }) ];
  };

  # script that will be run for this particular test
  testScript = ''
    ${createNamedMachine}
    ${createFailTestCase}
    ${installConfiguration}

    machine.start()

    ${hostnameFailTestCases}
    ${driveFailTestCases}

    # install configuration onto machine
    install_configuration("echo y | ${install-script}/bin/install.sh /dev/vda")
    machine.shutdown()

    # verify that client boots
    client = create_named_machine("client")
    client.start()

    # various checks to make sure client configured correctly
    assert "root" in client.succeed("hostname")
    assert "4G" in client.succeed("swapon --show | awk 'NR==2 {print $3}'")
    assert "/dev/vda2 on / type btrfs" in client.succeed("mount")
    assert "/dev/vda2 on /nix type btrfs" in client.succeed("mount")
    assert "/dev/vda2 on /persistent type btrfs" in client.succeed("mount")
    assert "/dev/vda2 on /swap type btrfs" in client.succeed("mount")
    assert "/dev/vda2 on /snapshots type btrfs" in client.succeed("mount")
    assert "/dev/vda1 on /boot type vfat" in client.succeed("mount")
  '';
}

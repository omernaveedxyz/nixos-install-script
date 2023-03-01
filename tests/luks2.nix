{ lib, pkgs, system ? builtins.currentSystem, ... }:

let

  helpers = import ./helpers { inherit lib pkgs system installedConfig; };
  inherit (helpers) install-script createNamedMachine createFailTestCase installConfiguration
    hostnameFailTestCases driveFailTestCases fidoFailTestCases;

  # Configuration of client machine afer installation.
  installedConfig = {
    imports = [ (import ./helpers/clientConfig.nix { hostName = "luks"; }) ];

    boot.initrd.luks.devices."luks".device = "/dev/disk/by-label/luks-luks";
  };

in
{
  name = "Luks Configuration Test p.2";

  # Configuration of machine for install.
  nodes.machine = {
    imports = [ (import ./helpers/machineConfig.nix { inherit lib; }) ];
  };

  # Script that will be run for this particular test.
  testScript = ''
    ${createNamedMachine}
    ${createFailTestCase}
    ${installConfiguration}

    machine.start()

    ${hostnameFailTestCases}
    ${driveFailTestCases}
    ${fidoFailTestCases}

    # Install configuration onto machine.
    install_configuration("echo -en \"y\nsupersecretpassword\n\" | ${install-script}/bin/install.sh --hostname=luks --enable-luks /dev/vda")
    machine.shutdown()

    # Verify that client boots.
    client = create_named_machine("client")
    client.start()
    client.wait_for_console_text("Starting password query on")
    client.send_console("supersecretpassword\n")
    client.wait_for_unit("multi-user.target")
        
    # Various checks to make sure client configured correctly.
    assert "luks" in client.succeed("hostname")
    assert "4G" in client.succeed("swapon --show | awk 'NR==2 {print $3}'")
    assert "/dev/mapper/luks on / type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /nix type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /persistent type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /swap type btrfs" in client.succeed("mount")
    assert "/dev/mapper/luks on /snapshots type btrfs" in client.succeed("mount")
    assert "/dev/vda1 on /boot type vfat" in client.succeed("mount")
  '';
}

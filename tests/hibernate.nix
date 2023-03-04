{ lib, pkgs, system ? builtins.currentSystem, ... }:

let

  helpers = import ./helpers { inherit lib pkgs system installedConfig; };
  inherit (helpers) install-script createNamedMachine createFailTestCase installConfiguration
    hostnameFailTestCases driveFailTestCases;

  # configuration of client machine afer installation
  installedConfig = {
    imports = [ (import ./helpers/clientConfig.nix { hostName = "hibernate"; }) ];

    fileSystems."/".options = [ "x-systemd.after=local-fs-pre.target" ];

    systemd.services.backdoor.conflicts = [ "sleep.target" ];
    powerManagement.resumeCommands = "systemctl --no-block restart backdoor.service";

    boot.resumeDevice = "/dev/disk/by-label/hibernate";
    boot.kernelParams = [ "mem_sleep_default=deep" "resume_offset=140544" ]; # manually calculated with: "btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile | systemd-cat"
    services.logind.lidSwitch = "suspend-then-hibernate";
    systemd.sleep.extraConfig = "HibernateDelaySec=1h";
  };

in
{
  name = "Hibernation Configuration Test";

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
    install_configuration("echo y | ${install-script}/bin/install.sh --hostname=hibernate --hibernation /dev/vda")
    machine.shutdown()

    # verify that client boots
    hibernate = create_named_machine("hibernate")
    hibernate.start()

    # various checks to make sure client configured correctly
    assert "hibernate" in hibernate.succeed("hostname")
    assert "8G" in hibernate.succeed("swapon --show | awk 'NR==2 {print $3}'")

    # drop in file that checks if we un-hibernated properly (and not booted fresh)
    hibernate.succeed(
      "mkdir /run/test",
      "mount -t ramfs -o size=1m ramfs /run/test",
      "echo not persisted to disk > /run/test/suspended",
    )

    # hibernate machine
    hibernate.execute("systemctl hibernate >&2 &", check_return=False)
    hibernate.wait_for_shutdown()

    # restore machine from hibernation, validate our ramfs file is there
    resume = create_named_machine("resume")
    resume.start()
    resume.succeed("grep 'not persisted to disk' /run/test/suspended")

    # ensure we don't restore from hibernation when booting again
    resume.crash()
    resume.wait_for_unit("default.target")
    resume.fail("grep 'not persisted to disk' /run/test/suspended")
  '';
}

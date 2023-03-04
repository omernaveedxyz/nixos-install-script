{ lib, pkgs, system, installedConfig }:

let

  script = import ../../script.nix { inherit pkgs; };
  inherit (script) usage installationScript;

in
rec {
  # do not execute nixos-install from script. Will be run manually in testScript
  install-script = (
    pkgs.writeShellScriptBin "install.sh" (
      builtins.replaceStrings [ "nixos-install --no-root-passwd" ] [ "" ] (
        builtins.readFile "${installationScript}/bin/installationScript"
      )
    )
  );

  # module used to mount client system configuration correctly
  installedSystem = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit system;
    modules = [ installedConfig ];
  }).config.system.build.toplevel;

  # function to quickly create machines within the test script
  createNamedMachine = ''
    def create_named_machine(name):
      machine = create_machine(
        {
          "qemuFlags": "-cpu max ${
            if system == "x86_64-linux" then "-m 2048"
            else "-m 768 -enable-kvm -machine virt,gic-version=host"}",
          "hdaInterface": "virtio",
          "hda": "vm-state-machine/machine.qcow2",
          "name": name,
        }
      )
      driver.machines.append(machine)
      return machine
  '';

  # function to quickly create a test case to make sure that improper flags are returning the
  # correct error
  createFailTestCase = ''
    def create_fail_test_case(description, call):
      expected = machine.succeed(f"${usage}/bin/usage '{description}'")
      result = machine.fail(f"echo y | ${install-script}/bin/install.sh {call}")
      assert expected == result, f"Expected {expected}, got {result}"
  '';

  # function to quickly run the installation script and shutdown the installation machine
  installConfiguration = ''
    def install_configuration(call):
      machine.succeed(
        f"{call}",
        "nix-store --load-db < ${pkgs.closureInfo { rootPaths = [ installedSystem ]; }}/registration",
        "nixos-install --root /mnt --system ${installedSystem} --no-root-passwd --no-channel-copy >&2",
      )
  '';

  # test hostname flag fail test cases
  hostnameFailTestCases = ''
    create_fail_test_case("hostname cannot be empty", "--hostname /dev/vda")
    create_fail_test_case("hostname cannot end in hyphen", "--hostname=test- /dev/vda")
    create_fail_test_case("invalid character in hostname. Only alnum+hyphen allowed", "--hostname=test?vm /dev/vda")
    create_fail_test_case("hostname cannot be empty", "--hostname= /dev/vda")
  '';

  # test drive argument fail test cases
  driveFailTestCases = ''
    create_fail_test_case("must provide drive for installation", "")
    create_fail_test_case("invalid block device specified for drive path", "/dev/sda")
    create_fail_test_case("too many arguments", "/dev/sda /dev/vda")
  '';

  # test fido flag fail test cases
  fidoFailTestCases = ''
    create_fail_test_case("no FIDO2 devices detected", "--luks --fido2 /dev/vda")
  '';

  # test fido flag fail test cases
  fidoFailTestCases2 = ''
    create_fail_test_case("in order to use FIDO2, luks must be enabled.", "--hostname=fido --fido2 /dev/vda")
    create_fail_test_case("invalid FIDO2 device path specified", "--luks --fido2=/tmp/doesnotexist /dev/vda")
  '';
}

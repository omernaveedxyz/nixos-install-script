{
  lib,
  pkgs,
  ...
}: {
  name = "Hibernate Configuration Test";
  nodes = import ./common/nodes.nix {
    inherit lib pkgs;
    hibernation = true;
  };
  testScript = {nodes, ...}:
    ''
      startcommand = "${pkgs.qemu_test}/bin/qemu-kvm -cpu max -m 2048"
    ''
    + builtins.readFile ./common/testScript.py
    + ''
      disk_fail_test_cases()
      hostname_fail_test_cases()
      filesystem_fail_test_cases()
      fido_fail_test_cases()
      hibernation_fail_test_cases()
      confirmation_fail_test_cases()

      installation_script("echo yes | nixos-install-script --testing --hostname=hibernate --hibernation /dev/vda")

      swapfile_shutdown()
      base_shutdown()
      boot_new_machine()
      base_verification()
      swapfile_verification()
      hostname_verification("hibernate")
      disk_mounted_verification()
      swap_mounted_verification()
      hibernate_verification()
      shutdown()
    '';
}

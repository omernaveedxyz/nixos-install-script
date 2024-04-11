{
  lib,
  pkgs,
  ...
}: {
  name = "ZFS Configuration Test";
  nodes = import ./common/nodes.nix {inherit lib pkgs;};
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

      installation_script("echo yes | nixos-install-script --testing --filesystem zfs /dev/vda")

      base_shutdown()
      boot_new_machine()
      base_verification()
      hostname_verification("nixos")
      zfs_disk_mounted_verification("nixos")
      shutdown()
    '';
}

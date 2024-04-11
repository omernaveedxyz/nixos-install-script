{
  lib,
  pkgs,
  ...
}: {
  name = "ZFS+LUKS Configuration Test";
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

      installation_script("echo -en \"yes\nsupersecretpassword\n\" | nixos-install-script --testing --hostname=luks --luks --filesystem zfs /dev/vda")

      base_shutdown()
      boot_new_machine()
      decrypt_luks()
      base_verification()
      hostname_verification("luks")
      zfs_disk_mounted_verification("luks")
      shutdown()
    '';
}

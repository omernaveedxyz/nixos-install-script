{
  lib,
  pkgs,
  ...
}: {
  name = "LUKS+Hibernate Configuration Test";
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
      fido_fail_test_cases()
      confirmation_fail_test_cases()

      installation_script("echo -en \"yes\nsupersecretpassword\n\" | nixos-install-script --testing --hostname=luks-hibernate --hibernation --luks /dev/vda")

      swapfile_shutdown()
      base_shutdown()
      boot_new_machine()
      decrypt_luks()
      base_verification()
      swapfile_verification()
      hostname_verification("luks-hibernate")
      encrypted_disk_mounted_verification("luks-hibernate")
      encrypted_swap_mounted_verification("luks-hibernate")
      encrypted_hibernate_verification()
      shutdown()
    '';
}

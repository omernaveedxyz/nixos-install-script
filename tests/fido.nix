{
  lib,
  pkgs,
  ...
}: {
  name = "FIDO Configuration Test";
  nodes = import ./common/nodes.nix {
    inherit lib pkgs;
    fido = true;
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

      installation_script("echo yes | nixos-install-script --testing --hostname=fido --luks --fido /dev/vda")
      recovery = machine.succeed("cat luks-recovery.txt").strip()

      base_shutdown()
      boot_new_machine()
      decrypt_fido(recovery)
      base_verification()
      hostname_verification("fido")
      encrypted_disk_mounted_verification("fido")
      shutdown()
    '';
}

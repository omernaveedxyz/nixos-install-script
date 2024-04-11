import os

image_dir = machine.state_dir
disk_image = os.path.join(image_dir, "machine.qcow2")
startcommand += f" -drive file={disk_image},if=virtio,werror=report"

def create_machine_named(name):
    return create_machine(startcommand, name=name)

machine.start()

with subtest("Assert readiness of login prompt"):
    machine.succeed("echo hello")

with subtest("Wait for hard disks to appear in /dev"):
    machine.succeed("udevadm settle")

##############
# VALIDATION #
##############

def create_fail_test_case(call):
    machine.fail(f"nixos-install-script {call}")

def disk_fail_test_cases():
    with subtest("Check that incorrect disk parameter fails"):
        create_fail_test_case("")
        create_fail_test_case("/dev/sda")
        create_fail_test_case("/dev/sda /dev/vda")

def hostname_fail_test_cases():
    with subtest("Check that incorrect hostname parameter fails"):
        create_fail_test_case("--hostname")
        create_fail_test_case("--hostname= /dev/vda")
        create_fail_test_case("--hostname=- /dev/vda")
        create_fail_test_case("--hostname=inc0r^ct /dev/vda")
        create_fail_test_case("--hostname=1111111111111111111111111111111111111111111111111111111111111111 /dev/vda")

def filesystem_fail_test_cases():
    with subtest("Check that incorrect filesystem parameter fails"):
        create_fail_test_case("--filesystem")
        create_fail_test_case("--filesystem= /dev/vda")
        create_fail_test_case("--filesystem=ext4 /dev/vda")

def fido_fail_test_cases():
    with subtest("Check that incorrect fido parameter fails"):
        create_fail_test_case("--fido /dev/vda")

def hibernation_fail_test_cases():
    with subtest("Check that incorrect filesystem parameter fails with hibernation"):
        create_fail_test_case("--hibernation --filesystem=zfs /dev/vda")

def confirmation_fail_test_cases():
    with subtest("Check that declining confirmation works"):
        machine.succeed("echo no | nixos-install-script /dev/vda")

################
# INSTALLATION #
################

def installation_script(call):
    with subtest("Check that the installation script runs to completion"):
        machine.succeed(call)

################
# VERIFICATION #
################

def base_shutdown():
    with subtest("Shutdown system after installation)"):
        machine.succeed("umount -R /mnt")
        machine.succeed("sync")
        machine.shutdown()

def swapfile_shutdown():
    with subtest("Disable swap"):
        machine.succeed("swapoff /mnt/swap/swapfile")

def boot_new_machine():
    global machine
    machine = create_machine_named("boot-after-install")

def decrypt_luks():
    machine.start()
    machine.wait_for_console_text("Starting password query on")
    machine.send_console("supersecretpassword\n")

def decrypt_fido(recovery):
    machine.start()
    machine.wait_for_console_text("Starting password query on")
    machine.send_console(recovery + "\n")

def base_verification():
    with subtest("Assert that /boot get mounted"):
        machine.wait_for_unit("local-fs.target")
        machine.succeed("test -e /boot/grub")

    with subtest("Check whether /root has correct permissions"):
        assert "700" in machine.succeed("stat -c '%a' /root")

def swapfile_verification():
    with subtest("Assert swap device got activated"):
        machine.wait_for_unit("swap.target")
        machine.succeed("cat /proc/swaps | grep -q /swap/swapfile")

def hostname_verification(hostname):
    with subtest("Check that hostname is set correctly"):
        assert hostname in machine.succeed("hostname")

def disk_mounted_verification():
    with subtest("Check whether drive is mounted correctly"):
        assert "/dev/vda1 on /boot type vfat" in machine.succeed("mount")
        assert "/dev/vda2 on /nix type btrfs" in machine.succeed("mount")
        assert "/dev/vda2 on /persistent type btrfs" in machine.succeed("mount")
        assert "/dev/vda2 on /snapshots type btrfs" in machine.succeed("mount")
        assert "/dev/vda2 on /var/log type btrfs" in machine.succeed("mount")

def zfs_disk_mounted_verification(hostname):
    with subtest("Check whether drive is mounted correctly"):
        assert "/dev/vda1 on /boot type vfat" in machine.succeed("mount")
        assert hostname + "/nix on /nix type zfs" in machine.succeed("mount")
        assert hostname + "/persistent on /persistent type zfs" in machine.succeed("mount")
        assert hostname + "/log on /var/log type zfs" in machine.succeed("mount")

def encrypted_disk_mounted_verification(hostname):
    with subtest("Check whether drive is mounted correctly"):
        assert "/dev/vda1 on /boot type vfat" in machine.succeed("mount")
        assert "/dev/mapper/" + hostname + " on /nix type btrfs" in machine.succeed("mount")
        assert "/dev/mapper/" + hostname + " on /persistent type btrfs" in machine.succeed("mount")
        assert "/dev/mapper/" + hostname + " on /snapshots type btrfs" in machine.succeed("mount")
        assert "/dev/mapper/" + hostname + " on /var/log type btrfs" in machine.succeed("mount")

def swap_mounted_verification():
    with subtest("Check that swap subvolume is mounted correctly"):
        assert "/dev/vda2 on /swap type btrfs" in machine.succeed("mount")
        assert "8G" in machine.succeed("swapon --show | awk 'NR==2 {print $3}'")

def encrypted_swap_mounted_verification(hostname):
    with subtest("Check that swap subvolume is mounted correctly"):
        assert "/dev/mapper/" + hostname + " on /swap type btrfs" in machine.succeed("mount")
        assert "8G" in machine.succeed("swapon --show | awk 'NR==2 {print $3}'")

def hibernate_verification():
    with subtest("Check that hibernation works correctly"):
        # drop in file that checks if we un-hibernated properly (and not booted fresh)
        machine.succeed("mkdir /run/test")
        machine.succeed("mount -t ramfs -o size=1m ramfs /run/test")
        machine.succeed("echo not persisted to disk > /run/test/suspended")

        # hibernate machine
        machine.execute("systemctl hibernate >&2 &", check_return=False)
        machine.wait_for_shutdown()

        # restore machine from hibernation, validate our ramfs file is there
        machine.start()
        machine.succeed("grep 'not persisted to disk' /run/test/suspended")

        # ensure we don't restore from hibernation when booting again
        machine.crash()
        machine.wait_for_unit("default.target")
        machine.fail("grep 'not persisted to disk' /run/test/suspended")

def encrypted_hibernate_verification():
    with subtest("Check that hibernation works correctly"):
        # drop in file that checks if we un-hibernated properly (and not booted fresh)
        machine.succeed("mkdir /run/test")
        machine.succeed("mount -t ramfs -o size=1m ramfs /run/test")
        machine.succeed("echo not persisted to disk > /run/test/suspended")

        # hibernate machine
        machine.execute("systemctl hibernate >&2 &", check_return=False)
        machine.wait_for_shutdown()

        # restore machine from hibernation, validate our ramfs file is there
        machine.start()
        decrypt_luks()
        machine.succeed("grep 'not persisted to disk' /run/test/suspended")

        # ensure we don't restore from hibernation when booting again
        machine.crash()
        machine.start()
        decrypt_luks()
        machine.wait_for_unit("default.target")
        machine.fail("grep 'not persisted to disk' /run/test/suspended")

def shutdown():
    machine.shutdown()

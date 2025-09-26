/*
  Package: parted
  Description: GNU command-line partition editor for creating, resizing, and managing disk partitions.
  Homepage: https://www.gnu.org/software/parted/
  Documentation: https://www.gnu.org/software/parted/manual/parted.html
  Repository: https://git.savannah.gnu.org/git/parted.git

  Summary:
    * Manages MBR, GPT, and other partition tables with support for resizing, moving, and copying partitions along with filesystem-aware operations.
    * Offers interactive shell and scripting modes suitable for automated disk provisioning.

  Options:
    parted <device> print: Display partition table information.
    parted <device> mklabel gpt: Create a GPT partition table.
    parted <device> mkpart <name> <fs> start end: Create partitions with explicit start/end positions.
    --script: Run in non-interactive mode for automation.
    resizepart <num> <end>: Resize a partition to a new end sector.

  Example Usage:
    * `sudo parted /dev/sda print` — Inspect current partitions on a disk.
    * `sudo parted --script /dev/sdb mklabel gpt mkpart primary ext4 1MiB 100GiB` — Create a GPT disk and an ext4 partition via a script.
    * `sudo parted /dev/nvme0n1 resizepart 3 200GiB` — Grow partition 3 to a new size.
*/

{
  flake.nixosModules.apps.parted =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.parted ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.parted ];
    };
}

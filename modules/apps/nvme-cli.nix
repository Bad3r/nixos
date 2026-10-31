/*
  Package: nvme-cli
  Description: Command-line interface for managing NVMe SSD devices on Linux.
  Homepage: https://github.com/linux-nvme/nvme-cli
  Documentation: https://docs.kernel.org/admin-guide/nvme.html
  Repository: https://github.com/linux-nvme/nvme-cli

  Summary:
    * Provides tools to query NVMe controller information, SMART data, namespaces, and perform firmware updates or format commands.
    * Supports monitoring health, running self-tests, and interacting with NVMe over Fabrics targets.

  Options:
    nvme list: Enumerate detected NVMe devices and namespaces.
    nvme smart-log /dev/nvme0: Display SMART/health info for a drive.
    nvme format /dev/nvme0n1 --force: Format a namespace (destructive, use with caution).
    nvme fw-log /dev/nvme0: Inspect firmware slots.
    nvme device-self-test /dev/nvme0 --start short: Run a short self-test.

  Notes:
    * Device commands need `sudo`.
*/
_:
let
  NvmeCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nvme-cli".extended;
    in
    {
      options.programs.nvme-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nvme-cli.";
        };

        package = lib.mkPackageOption pkgs "nvme-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nvme-cli = NvmeCliModule;
}

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

  Example Usage:
    * `nvme list` -- Discover NVMe devices attached to the system.
    * `nvme smart-log /dev/nvme0` -- Check drive temperature, media errors, and wear indicators.
    * `nvme device-self-test /dev/nvme0 --start extended` -- Initiate an extended diagnostic self-test.

  Notes:
    * `disk` group members run this without `sudo`: a capability wrapper supplies CAP_SYS_ADMIN and the shared storage policy opens the controller char nodes.
    * The wrapper covers the whole binary, so destructive subcommands (`format`, `sanitize`, `fw-commit`) also lose the sudo prompt.
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

        # nvme_cmd_allowed() rejects every admin passthrough except a few
        # identify CNS values without CAP_SYS_ADMIN, so smart-log, error-log,
        # fw-log and telemetry fail with EACCES for a plain `disk` member.
        security.wrappers.nvme = {
          source = "${cfg.package}/bin/nvme";
          capabilities = "cap_sys_admin+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.nvme-cli = NvmeCliModule;
}

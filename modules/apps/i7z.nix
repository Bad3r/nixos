/*
  Package: i7z
  Description: Better i7 (and now i3, i5) reporting tool for Linux.
  Homepage: https://github.com/DimitryAndric/i7z
  Documentation: https://github.com/DimitryAndric/i7z
  Repository: https://github.com/DimitryAndric/i7z

  Summary:
    * Shows per-core CPU frequencies, multipliers, and C-state residency in real time.
    * Supports socket-specific monitoring and logging frequency samples for later analysis.

  Options:
    --nogui: Turn off the ncurses interface output.
    -w, --write <a|l>: Write samples to a log file in append or replace mode.
    -l, --logfile <path>: Use a custom log file path instead of the default filename.
    --socket0 <id>: Select which socket ID to display as the primary package.
    --socket1 <id>: Select a secondary socket ID for dual-socket monitoring.

  Notes:
    * Installs a `security.wrappers.i7z` capability wrapper so `i7z` can run without sudo.
    * Enables `hardware.cpu.x86.msr` because i7z reads model-specific registers.
    * Restricts the privileged wrapper to the configured owner account only.
    * Grants MSR device access through a dedicated `msr` group.
*/
_:
let
  I7zModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.i7z.extended;
      owner = metaOwner.username or (throw "i7z module: expected metaOwner.username to be defined");
    in
    {
      options.programs.i7z.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable i7z.";
        };

        package = lib.mkPackageOption pkgs "i7z" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        hardware.cpu.x86.msr = {
          enable = true;
          # udev OWNER must be a system account; regular users are ignored.
          owner = "root";
          group = "msr";
          # i7z validates W_OK on /dev/cpu/*/msr before starting.
          mode = "0660";
        };

        users.users.${owner}.extraGroups = lib.mkAfter [ config.hardware.cpu.x86.msr.group ];

        # Ensure existing MSR device nodes are relabeled on activation.
        # Some systems keep /dev/cpu/*/msr at kernel defaults until explicitly
        # adjusted, even when the udev rule is present.
        system.activationScripts.i7z-msr-permissions = {
          deps = [ "specialfs" ];
          text = ''
            if [ -d /dev/cpu ]; then
              for msr in /dev/cpu/*/msr; do
                [ -e "$msr" ] || continue
                chown root:${config.hardware.cpu.x86.msr.group} "$msr"
                chmod ${config.hardware.cpu.x86.msr.mode} "$msr"
              done
            fi
          '';
        };

        security.wrappers.i7z = {
          owner = owner;
          group = config.hardware.cpu.x86.msr.group;
          permissions = "u+rx,g-rwx,o-rwx";
          source = lib.getExe cfg.package;
          capabilities = "cap_sys_rawio=ep";
        };
      };
    };
in
{
  flake.nixosModules.apps.i7z = I7zModule;
}

{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

  fileSharingAppNames = [
    "qbittorrent"
    "localsend"
    "rclone"
    "rsync"
    "nicotine"
    "filen-cli"
    "filen-desktop"
    "dropbox"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps fileSharingAppNames;
}

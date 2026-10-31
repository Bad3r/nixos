/*
  Package: keepassxc
  Description: Offline password manager with many features.
  Homepage: https://keepassxc.org/
  Documentation: https://keepassxc.org/docs/
  Repository: https://github.com/keepassxreboot/keepassxc

  Summary:
    * Opens KeePass-compatible encrypted databases for offline secret storage, editing, and search.
    * Supports browser integration, TOTP generation, SSH agent integration, and hardware-backed unlock methods.
*/
_:
let
  KeepassxcModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.keepassxc.extended;
    in
    {
      options.programs.keepassxc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable keepassxc.";
        };

        package = lib.mkPackageOption pkgs "keepassxc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.keepassxc = KeepassxcModule;
}

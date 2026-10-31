/*
  Package: libsecret
  Description: Library and CLI (`secret-tool`) for storing and retrieving passwords through the freedesktop.org Secret Service.
  Homepage: https://gitlab.gnome.org/GNOME/libsecret
  Documentation: https://gnome.pages.gitlab.gnome.org/libsecret/
  Repository: https://gitlab.gnome.org/GNOME/libsecret

  Summary:
    * Stores, looks up, and clears keyring items addressed by attribute pairs.

  Options:
    secret-tool store --label=<label> <attribute> <value>...: Store a secret read from the terminal under the given attributes.
    secret-tool lookup <attribute> <value>...: Print the secret matching the attributes.
    secret-tool clear <attribute> <value>...: Remove the matching items.
*/
_:
let
  LibsecretModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libsecret.extended;
    in
    {
      options.programs.libsecret.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable libsecret.";
        };

        package = lib.mkPackageOption pkgs "libsecret" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.libsecret = LibsecretModule;
}

/*
  Package: localsend
  Description: Cross-platform, open-source AirDrop alternative for offline file transfers.
  Homepage: https://localsend.org/
  Documentation: https://localsend.org/docs/
  Repository: https://github.com/localsend/localsend

  Summary:
    * Discovers nearby devices on the local network and transfers files over TLS without internet connectivity.
    * Sends files, text snippets, and links between desktop and mobile platforms.
*/
_:
let
  LocalsendModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.localsend.extended;
    in
    {
      options.programs.localsend.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable localsend.";
        };

        package = lib.mkPackageOption pkgs "localsend" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # LocalSend uses port 53317 for both TCP (file transfer) and UDP (discovery)
        networking.firewall = {
          allowedTCPPorts = [ 53317 ];
          allowedUDPPorts = [ 53317 ];
        };
      };
    };
in
{
  flake.nixosModules.apps.localsend = LocalsendModule;
}

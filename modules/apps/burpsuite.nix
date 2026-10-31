/*
  Package: burpsuite
  Description: Burp Suite Community Edition — integrated platform for web application security testing.
  Homepage: https://portswigger.net/burp/communitydownload
  Documentation: https://portswigger.net/burp/documentation
  Repository: nil

  Summary:
    * Ships an intercepting proxy, repeater, and decoder for manual web pentesting; advanced scanning requires the Professional edition.
*/
_:
let
  BurpsuiteModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.burpsuite.extended;
    in
    {
      options.programs.burpsuite.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Burp Suite Community Edition.";
        };

        package = lib.mkPackageOption pkgs "burpsuite" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "burpsuite" ];
  flake.nixosModules.apps.burpsuite = BurpsuiteModule;
}

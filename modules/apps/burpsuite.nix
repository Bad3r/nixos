/*
  Package: burpsuite
  Description: Burp Suite Community Edition — integrated platform for web application security testing.
  Homepage: https://portswigger.net/burp/communitydownload
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/bu/burpsuite

  Summary:
    * Provides the Community Edition launcher (`burpsuite`) packaged from upstream nixpkgs.
    * Ships an intercepting proxy, repeater, and decoder for manual web pentesting; advanced scanning requires the Professional edition module.

  Options:
    burpsuite: Launch Burp Suite Community Edition inside its FHS environment.
    BURP_JVM_ARGS="-Xmx4G" burpsuite: Increase JVM heap for larger engagements.
    JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" burpsuite: Pass additional Java flags to the launcher.

  Example Usage:
    * `burpsuite` -- Start Burp Suite and configure the browser proxy to intercept traffic.
    * `BURP_JVM_ARGS="-Xmx8G" burpsuite` -- Allocate a larger heap for crawling large applications.
    * Enable `programs.burpsuitepro.extended` separately for the Professional edition module.
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

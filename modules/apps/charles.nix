/*
  Package: charles
  Description: Desktop web debugging proxy for inspecting and modifying HTTP(S) traffic.
  Homepage: https://www.charlesproxy.com/
  Documentation: https://www.charlesproxy.com/documentation/
  Repository: nil

  Summary:
    * Provides the Charles proxy GUI packaged from the repo-local `packages/charles` derivation.
    * Supports SSL proxying, repeat requests, bandwidth shaping, and session recording for web/API testing.

  Options:
    charles: Launch the Charles desktop proxy UI.
    ~/.charles.config: User-level configuration directory consumed by the packaged launcher.

  Notes:
    * Requires `pkgs.charles` from the host custom-packages overlay.
*/
_:
let
  CharlesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.charles.extended;
    in
    {
      options.programs.charles.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable charles.";
        };

        package = lib.mkPackageOption pkgs "charles" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "charles" ];
  flake.nixosModules.apps.charles = CharlesModule;
}

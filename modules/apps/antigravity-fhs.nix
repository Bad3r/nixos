/*
  Package: antigravity-fhs
  Description: Google's AI-powered agentic development platform in FHS environment.
  Homepage: https://antigravity.google/
  Documentation: https://developers.google.com/antigravity/docs
  Repository: https://github.com/nicholasgriffintn/antigravity-nix

  Summary:
    * AI-powered IDE built on VS Code with autonomous agent capabilities for code generation, execution, and verification.
    * FHS-wrapped variant enabling seamless extension compatibility without Nix-specific modifications.
*/
_:
let
  AntigravityFhsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-fhs".extended;
    in
    {
      options.programs."antigravity-fhs".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable antigravity-fhs.";
        };

        package = lib.mkPackageOption pkgs "antigravity-fhs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."antigravity-fhs" = AntigravityFhsModule;
}

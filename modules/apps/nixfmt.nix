/*
  Package: nixfmt
  Description: Official formatter for Nix code.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/NixOS/nixfmt

  Summary:
    * Formats Nix source code using the official RFC 166 style.
    * Supports check and verification modes for formatter automation.

  Options:
    -c: Check whether files are formatted without modifying them.
    -f: Provide a display filename for stdin input.
    -s: Enable stricter formatting.
    -v: Verify formatted output.
    -w: Set the maximum output width.
*/
_:
let
  NixfmtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nixfmt.extended;
    in
    {
      options.programs.nixfmt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nixfmt.";
        };

        package = lib.mkPackageOption pkgs "nixfmt" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nixfmt = NixfmtModule;
}

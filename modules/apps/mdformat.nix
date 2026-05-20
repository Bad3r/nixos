/*
  Package: mdformat
  Description: CommonMark compliant Markdown formatter.
  Homepage: https://mdformat.readthedocs.io/
  Documentation: https://mdformat.readthedocs.io/
  Repository: https://github.com/hukkin/mdformat

  Summary:
    * Formats Markdown files while preserving CommonMark-compatible structure.
    * Includes the GitHub Flavored Markdown plugin used by the central treefmt configuration.

  Options:
    --check: Verify formatting without applying changes.
    --end-of-line: Select output line endings.
    --number: Apply consecutive numbering to ordered lists.
    --wrap: Control paragraph word wrapping.

  Notes:
    * Default package wraps mdformat with mdformat-gfm to match the repository formatter.
*/
_:
let
  MdformatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mdformat.extended;
    in
    {
      options.programs.mdformat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mdformat.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.mdformat.withPlugins (ps: [ ps.mdformat-gfm ]);
          defaultText = lib.literalExpression "pkgs.mdformat.withPlugins (ps: [ ps.mdformat-gfm ])";
          description = "The mdformat package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mdformat = MdformatModule;
}

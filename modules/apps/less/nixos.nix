/*
  Package: less
  Description: Feature-rich pager for viewing text files and command output.
  Homepage: https://www.greenwoodsoftware.com/less/
  Documentation: https://www.greenwoodsoftware.com/less/faq.html
  Repository: https://github.com/gwsw/less

  Summary:
    * Supports forward/backward navigation, search, and terminal-aware rendering for large texts.
    * Provides customization through environment variables, key bindings, and syntax-aware options.

  Options:
    +F <file>: Follow file updates similar to `tail -f` while viewing in less.
    -R <file>: Display raw control characters for colored output.
    -N <file>: Show line numbers along the left margin.
*/
_:
let
  LessModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.less.extended;
    in
    {
      options.programs.less.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable less.";
        };

        package = lib.mkPackageOption pkgs "less" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.less = LessModule;
}

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

{
  flake.nixosModules.apps.less =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.less ];
    };
}

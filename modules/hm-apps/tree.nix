/*
  Package: tree
  Description: Command to produce a depth indented directory listing.
  Homepage: https://oldmanprogrammer.net/source.php?dir=projects/tree
  Documentation: https://linux.die.net/man/1/tree
  Repository: https://gitlab.com/OldManProgrammer/unix-tree

  Summary:
    * Recursively lists directories as a visual tree with optional colorization, file metadata, and depth control.
    * Supports filtering by patterns, printing full paths, showing permissions, and generating JSON/CSV outputs.

  Options:
    -L <depth>: Limit recursion depth when rendering the tree.
    -a: Include hidden files in the listing.
    -I <pattern>: Exclude files or directories matching a glob pattern.
    -H <url>: Generate HTML output with links relative to a base URL.

  Example Usage:
    * `tree -L 2` — Summarize the current directory up to two levels deep.
    * `tree -a -I '.git|node_modules'` — Show hidden files but exclude Git metadata and dependencies.
    * `tree -H '.' -o tree.html` — Produce a browsable HTML directory listing for publishing.
*/

{
  flake.homeManagerModules.apps.tree =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tree.extended;
    in
    {
      options.programs.tree.extended = {
        enable = lib.mkEnableOption "Command to produce a depth indented directory listing.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.tree ];
      };
    };
}

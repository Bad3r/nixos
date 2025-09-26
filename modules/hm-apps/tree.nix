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
    tree: Print directory contents recursively starting from the current directory.
    tree -L <depth>: Limit recursion depth.
    tree -a: Include hidden files in the listing.
    tree -I <pattern>: Exclude files/directories matching a glob pattern.
    tree -H <url>: Generate HTML output with links to files relative to a base URL.

  Example Usage:
    * `tree -L 2` — Summarize the current directory up to two levels deep.
    * `tree -a -I '.git|node_modules'` — Show hidden files but exclude Git metadata and dependencies.
    * `tree -H '.' -o tree.html` — Produce a browsable HTML directory listing for publishing.
*/

{
  flake.homeManagerModules.apps.tree =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.tree ];
    };
}

/*
  Package: dua
  Description: Tool to conveniently learn about the disk usage of directories.
  Homepage: https://github.com/Byron/dua-cli
  Documentation: https://github.com/Byron/dua-cli#readme
  Repository: https://github.com/Byron/dua-cli

  Summary:
    * Scans directories in parallel and presents interactive or batch summaries of disk usage.
    * Supports deletion workflows, JSON output, and navigation similar to `ncdu` with blazing-fast Rust performance.

  Options:
    dua: Launch the interactive TUI in the current directory.
    dua --summarize <paths>: Print a non-interactive usage summary for paths.
    dua i <path>: Open the interactive inspector rooted at a path.
    dua --format human|bytes|si: Control how sizes are rendered.
    dua cache clear: Remove cached traversal data.

  Example Usage:
    * `dua` — Inspect disk usage interactively starting at the current working directory.
    * `dua --summarize ~/Downloads ~/Videos` — Compare storage consumption across multiple directories.
    * `dua i /var/log` — Drill into nested directories and delete files directly from the TUI.
*/

{
  flake.homeManagerModules.apps.dua =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.dua ];
    };
}

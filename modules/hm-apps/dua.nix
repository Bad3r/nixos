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
    --summarize <paths>: Print non-interactive disk-usage summaries for one or more paths.
    --format human|bytes|si: Control how sizes are rendered in batch output.
    --version: Display the installed dua-cli version.

  Example Usage:
    * `dua` — Inspect disk usage interactively starting at the current working directory.
    * `dua --summarize ~/Downloads ~/Videos` — Compare storage consumption across multiple directories.
    * `dua i /var/log` — Drill into nested directories and delete files directly from the TUI.
*/

_: {
  flake.homeManagerModules.apps.dua =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "dua" "extended" "enable" ] false osConfig;
    in
    {
      # Package installed by NixOS module; HM provides user-level config if needed
      config = lib.mkIf nixosEnabled {
        # dua doesn't have HM programs.dua module - config managed by app itself
      };
    };
}

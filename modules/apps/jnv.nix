/*
  Package: jnv
  Description: Interactive CLI JSON viewer and jq playground built with TUI controls.
  Homepage: https://github.com/ynqa/jnv
  Documentation: https://github.com/ynqa/jnv#usage
  Repository: https://github.com/ynqa/jnv

  Summary:
    * Provides a curses-based interface for exploring JSON documents and crafting jq filters with live previews.
    * Ideal for debugging APIs or log payloads, with support for loading files or piping data via stdin.

  Options:
    jnv <file>: Load JSON from a file into the viewer (stdin supported when omitted).
    -o, --output <path>: Save filtered results to a file.
    --color <auto|always|never>: Control colorized output.
    --wrap: Toggle line wrapping for the preview pane.

  Example Usage:
    * `jnv response.json` — Explore a JSON response interactively and experiment with jq filters.
    * `curl https://api.example.com | jnv` — Pipe API output directly into the viewer.
    * `jnv data.json --output filtered.json` — Save the filtered JSON result while experimenting in the TUI.
*/

{
  flake.nixosModules.apps.jnv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jnv ];
    };
}

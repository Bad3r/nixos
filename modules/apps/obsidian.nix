/*
  Package: obsidian
  Description: Local-first Markdown knowledge base and note-taking app with graph-based linking.
  Homepage: https://obsidian.md/
  Documentation: https://help.obsidian.md/
  Repository: https://github.com/obsidianmd/obsidian-releases (binary releases)

  Summary:
    * Organizes notes as Markdown files with bidirectional links, graph view, daily notes, templates, and extensible plugin marketplace.
    * Supports end-to-end encrypted sync (paid), community themes, and plugins for task management, spaced repetition, and more.

  Options:
    obsidian: Launch the desktop application.
    Command palette (Ctrl+P): Access actions like quick switcher, open vaults, toggle themes.
    Settings → Community Plugins: Install or enable third-party plugins.

  Example Usage:
    * `obsidian` — Open the vault selector or launch the most recent vault.
    * Create `~/Notes` and add as a vault to manage Markdown notes locally.
    * Enable Plugins → “Daily Notes” to generate journal entries automatically.
*/

{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];

  flake.nixosModules.apps.obsidian =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.obsidian ];
    };

}

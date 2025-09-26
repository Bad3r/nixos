/*
  Package: copyq
  Description: Clipboard manager with advanced features.
  Homepage: https://hluk.github.io/CopyQ/
  Documentation: https://hluk.github.io/CopyQ/docs/
  Repository: https://github.com/hluk/CopyQ

  Summary:
    * Provides a history of clipboard entries with search, filtering, encryption, and scriptable actions.
    * Supports cross-platform tray integration, tabbed clip organization, and synchronization through commands or plugins.

  Options:
    copyq: Launch the system tray daemon and clipboard UI.
    copyq toggle: Show or hide the main window via CLI.
    copyq add <text>: Append custom text into the clipboard history.
    copyq paste <index>: Paste a stored item directly into the focused window.
    copyq config <key> <value>: Adjust runtime configuration settings.

  Example Usage:
    * `copyq` — Start the clipboard manager and expose the tray icon to manage history entries.
    * `copyq add "ssh prod.example.com"` — Store frequently used snippets without copying them manually.
    * `copyq paste 0` — Paste the most recent clipboard item through a script or key binding.
*/

{
  flake.homeManagerModules.apps.copyq =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.copyq ];
    };
}

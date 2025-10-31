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
    --start-server: Launch the system tray daemon without opening the UI immediately.
    --toggle: Show or hide the main window via the running daemon.
    --insert <text>: Append custom text into the clipboard history from the CLI.
    --paste <index>: Paste a stored item directly into the focused window.

  Example Usage:
    * `copyq` — Start the clipboard manager and expose the tray icon to manage history entries.
    * `copyq add "ssh prod.example.com"` — Store frequently used snippets without copying them manually.
    * `copyq paste 0` — Paste the most recent clipboard item through a script or key binding.
*/

{
  flake.homeManagerModules.apps.copyq =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.copyq.extended;
    in
    {
      options.programs.copyq.extended = {
        enable = lib.mkEnableOption "Clipboard manager with advanced features.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.copyq ];
      };
    };
}

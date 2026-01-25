/*
  Package: gpg-tui
  Description: Terminal user interface for managing GnuPG keys and operations.
  Homepage: https://github.com/orhun/gpg-tui
  Documentation: https://github.com/orhun/gpg-tui#usage
  Repository: https://github.com/orhun/gpg-tui

  Summary:
    * Presents a TUI dashboard for listing keys, signing, revoking, exporting, and editing trust without memorizing GPG CLI options.
    * Integrates with `gpg-agent` and provides search, filtering, and keyboard-driven workflows for keyring maintenance.

  Options:
    gpg-tui: Launch the interface; navigation and operations are performed with keyboard shortcuts.
    -k, --key <fingerprint>: Focus a specific key on startup.
    --lang <locale>: Choose UI language if translations are available.

  Example Usage:
    * `gpg-tui` -- Open the TUI to manage local and imported keys interactively.
    * Within the UI, use `S` to sign a selected key or `E` to export it.
    * Press `?` inside the application to view the shortcut reference.
*/
_:
let
  GpgTuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."gpg-tui".extended;
    in
    {
      options.programs.gpg-tui.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gpg-tui.";
        };

        package = lib.mkPackageOption pkgs "gpg-tui" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gpg-tui = GpgTuiModule;
}

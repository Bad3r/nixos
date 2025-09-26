/*
  Package: arandr
  Description: Graphical front end for xrandr that lets you arrange displays by drag and drop.
  Homepage: https://christian.amsuess.com/tools/arandr/
  Documentation: https://christian.amsuess.com/tools/arandr/
  Repository: https://gitlab.com/arandr/arandr

  Summary:
    * Provides a simple GTK interface to position, rotate, and enable multiple monitors with live xrandr output.
    * Saves layouts as executable shell scripts so arrangements can be re-applied without using the GUI.

  Options:
    --version: Print the ARandR release number and exit.
    -h, --help: Show command usage and exit.
    --randr-display=DISPLAY: Query xrandr information from DISPLAY while keeping the UI local.
    --force-version: Skip xrandr version safeguards when working with newer servers.
    [savedfile]: Load and apply a previously exported layout script on startup.

  Example Usage:
    * `arandr` — Launch the visual display layout editor and manage monitors interactively.
    * `arandr ~/.screenlayout/work.sh` — Open the GUI with a saved layout preloaded for edits.
    * `arandr --randr-display 192.168.0.10:0` — Adjust outputs exposed by a remote X server over SSH forwarding.
*/

{
  flake.nixosModules.apps.arandr =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.arandr ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.arandr ];
    };
}

# Module: home/gui/chromium.nix
# Purpose: Chromium configuration
# Namespace: flake.modules.homeManager.gui
# Pattern: Home Manager GUI - Graphical application configuration

{
  flake.modules.homeManager.gui.programs.chromium = {
    enable = true;
    extensions = [
      # Bitwarden
      # https://chrome.google.com/webstore/detail/bitwarden-free-password-m/nngceckbapebfimnlniiiahkandclblb
      { id = "nngceckbapebfimnlniiiahkandclblb"; }
    ];
  };
}

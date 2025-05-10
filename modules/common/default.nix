{ config, pkgs, ... }:

{
  imports = [ ./locale.nix ./packages.nix ];

  # Programs
  programs.firefox.enable = true;
  programs.firefox.package = pkgs.firefox;
  programs.firefox.preferences = {
    "sidebar.verticalTabs" = true;
    "extensions.pocket.enabled" = false;
    "toolkit.telemetry.enabled" = false;
    "toolkit.telemetry.unified" = false;

  };

  programs.fish.enable = false;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
  };
}

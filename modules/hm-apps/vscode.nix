/*
  Package: vscode
  Description: Visual Studio Code - a lightweight but powerful source code editor.
  Homepage: https://code.visualstudio.com/
  Documentation: https://code.visualstudio.com/docs
  Repository: https://github.com/microsoft/vscode

  Summary:
    * Feature-rich code editor with IntelliSense, debugging, Git integration, and extensive extension marketplace.
    * Supports multiple languages, remote development, and customizable themes via Stylix.
    * Uses vscode-fhs package for better NixOS compatibility with extensions.

  Features:
    * Stylix theming integration for consistent colors
    * FHS environment for extension compatibility
    * Default profile themed automatically
    * Extensible via Home Manager configuration

  Example Usage:
    * `code .` — Open current directory in VS Code
    * `code file.ts` — Open a specific file
    * `code --install-extension ms-python.python` — Install extensions
*/

_: {
  flake.homeManagerModules.apps.vscode =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      enabled = lib.attrByPath [ "programs" "vscode-fhs" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf enabled {
        programs.vscode = {
          enable = true;

          # Use vscode-fhs for better extension compatibility on NixOS
          package = pkgs.vscode-fhs;

          # Stylix will automatically theme the "default" profile
          # Additional configuration can be added here:
          # userSettings = {
          #   "editor.fontSize" = 14;
          #   "editor.fontFamily" = "'FiraCode Nerd Font', monospace";
          #   "editor.fontLigatures" = true;
          #   "workbench.startupEditor" = "none";
          #   "editor.minimap.enabled" = false;
          #   "editor.rulers" = [ 80 120 ];
          # };
        };
      };
    };
}

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
    * `code .` -- Open current directory in VS Code
    * `code file.ts` -- Open a specific file
    * `code --install-extension ms-python.python` -- Install extensions
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
      themeExtension = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          hash = "sha256-XimGw20lrQDuCRHg9KK2vwLiVgaHRNkbbYWp11vpWns=";
          name = "onedark-zed";
          publisher = "premier213";
          version = "1.0.6";
        }
      ];
    in
    {
      config = lib.mkIf enabled {
        stylix.targets.vscode.enable = false;

        programs.vscode = {
          enable = true;
          package = null;
          profiles.default = {
            extensions = themeExtension;
            userSettings = {
              "workbench.colorTheme" = "OneDark Dark+ Vivid";
            };
          };
        };
      };
    };
}

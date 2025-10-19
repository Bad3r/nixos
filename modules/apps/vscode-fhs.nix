/*
  Package: vscode-fhs
  Description: Filesystem Hierarchy Standard (FHS) wrapped Visual Studio Code for better compatibility with extensions and language servers.
  Homepage: https://code.visualstudio.com/
  Documentation: https://code.visualstudio.com/docs
  Repository: https://github.com/microsoft/vscode

  Summary:
    * Runs VS Code inside an FHS environment to satisfy extensions expecting `/usr/lib`, glibc, or dynamic library paths not present on NixOS.
    * Bundles the proprietary Microsoft build with extra shell wrappers while retaining extension marketplace support.

  Options:
    code: Launch Visual Studio Code within the FHS wrapper.
    code --extensions-dir <dir>: Use a custom extension directory.
    code --user-data-dir <dir>: Store user settings in an alternate location.
    code --disable-gpu: Troubleshoot rendering issues on unsupported GPUs.

  Example Usage:
    * `code .` — Open the current directory in VS Code.
    * `code --disable-gpu --log trace` — Diagnose rendering problems with verbose logging.
    * Configure remote development extensions in the usual manner; the FHS wrapper ensures required binaries resolve correctly.
*/

{
  # App module that installs VS Code (FHS) when imported
  flake.nixosModules.apps."vscode-fhs" =
    { pkgs, ... }:
    {
      nixpkgs.allowedUnfreePackages = [
        "code"
        "vscode"
        "vscode-fhs"
      ];
      environment.systemPackages = [ pkgs.vscode-fhs ];
    };
}

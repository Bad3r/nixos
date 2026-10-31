/*
  Package: vscode-fhs
  Description: Filesystem Hierarchy Standard (FHS) wrapped Visual Studio Code for better compatibility with extensions and language servers.
  Homepage: https://code.visualstudio.com/
  Documentation: https://code.visualstudio.com/docs
  Repository: https://github.com/microsoft/vscode

  Summary:
    * Runs VS Code in an FHS environment, so extensions find the `/usr/lib` and glibc paths they expect.
    * Proprietary Microsoft build with extension marketplace support.

  Options:
    code --extensions-dir <dir>: Use a custom extension directory.
    code --user-data-dir <dir>: Store user settings in an alternate location.
    code --disable-gpu: Troubleshoot rendering issues on unsupported GPUs.
*/
_:
let
  VscodeFhsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."vscode-fhs".extended;
    in
    {
      options.programs.vscode-fhs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vscode-fhs.";
        };

        package = lib.mkPackageOption pkgs "vscode-fhs" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "code"
    "vscode"
  ];
  flake.nixosModules.apps.vscode-fhs = VscodeFhsModule;
}

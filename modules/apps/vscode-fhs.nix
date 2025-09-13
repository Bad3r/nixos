{
  # App module that installs VS Code (FHS) when imported
  flake.nixosModules.apps.vscodeFhs =
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

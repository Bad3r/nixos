{
  flake.nixosModules.apps."vscode" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."vscode" ];
    };
}

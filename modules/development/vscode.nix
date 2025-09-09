{
  nixpkgs.allowedUnfreePackages = [
    "code"
    "vscode"
    "vscode-fhs"
  ];

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vscode-fhs
      ];
    };
}

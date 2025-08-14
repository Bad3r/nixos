{
  nixpkgs.allowedUnfreePackages = [
    "code"
    "vscode"
    "vscode-fhs"
  ];

  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vscode-fhs
      ];
    };
}

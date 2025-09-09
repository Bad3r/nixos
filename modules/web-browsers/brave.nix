{
  nixpkgs.allowedUnfreePackages = [
    "brave"
  ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        brave
      ];
    };
}

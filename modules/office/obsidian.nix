{
  nixpkgs.allowedUnfreePackages = [
    "obsidian"
  ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        obsidian
      ];
    };
}

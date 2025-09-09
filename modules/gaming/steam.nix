{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      programs.steam = {
        enable = true;
        # Add Proton-GE (Glorious Eggroll) for enhanced game compatibility
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
    };
}

{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      programs.steam = {
        enable = true;
        # Add Proton-GE (Glorious Eggroll) for enhanced game compatibility
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
    };
}

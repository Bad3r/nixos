{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  flake.nixosModules =
    let
      steamModule =
        { pkgs, ... }:
        {
          programs.steam = {
            enable = true;
            # Add Proton-GE (Glorious Eggroll) for enhanced game compatibility
            extraCompatPackages = [ pkgs.proton-ge-bin ];
            extraPackages = with pkgs; [
              dwarfs
              fuse-overlayfs
              psmisc
            ];
          };
        };
    in
    {
      pc = steamModule;
      apps.steam = steamModule;
    };
}

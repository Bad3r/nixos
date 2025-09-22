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
      apps.steam = steamModule;
      pc = steamModule;
    };
}

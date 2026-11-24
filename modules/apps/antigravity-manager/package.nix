_: {
  nixpkgs.allowedUnfreePackages = [ "antigravity-manager" ];

  perSystem =
    { pkgs, ... }:
    {
      packages.antigravity-manager = pkgs.callPackage ../../../packages/antigravity-manager { };
    };
}

_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.camoufox = pkgs.callPackage ../../../packages/camoufox { };
    };
}

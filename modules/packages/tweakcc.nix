_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.tweakcc = pkgs.callPackage ../../packages/tweakcc { };
    };
}

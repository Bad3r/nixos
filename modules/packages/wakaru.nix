_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.wakaru = pkgs.callPackage ../../packages/wakaru { };
    };
}

_: {
  perSystem =
    { pkgs, ... }:
    {
      packages."duplicati-r2-list" = (pkgs.callPackage ../../packages/duplicati-r2-tools { }).list;
    };
}

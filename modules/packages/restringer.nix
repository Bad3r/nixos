_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.restringer = pkgs.callPackage ../../packages/restringer { };
    };
}

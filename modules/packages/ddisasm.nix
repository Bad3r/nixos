_: {
  perSystem =
    { config, pkgs, ... }:
    {
      packages.ddisasm = pkgs.callPackage ../../packages/ddisasm { };
      checks.ddisasm-roundtrip = config.packages.ddisasm.tests.roundtrip;
    };
}

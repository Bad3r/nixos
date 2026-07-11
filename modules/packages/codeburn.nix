_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.codeburn = pkgs.callPackage ../../packages/codeburn { };
    };
}

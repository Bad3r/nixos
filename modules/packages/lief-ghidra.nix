_: {
  perSystem =
    { config, pkgs, ... }:
    {
      packages.lief-ghidra = pkgs.callPackage ../../packages/lief-ghidra { };
      checks.lief-ghidra-headless = config.packages.lief-ghidra.tests.headless;
    };
}

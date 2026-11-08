{ self, ... }:
{
  configurations.nixos.songbird.module =
    { pkgs, ... }:
    {
      programs.ghidra.extended.extensions = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.lief-ghidra
      ];
    };
}

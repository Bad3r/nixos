{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = with pkgs; [
        biome
        shfmt
        nixfmt-rfc-style
        treefmt
      ];
    };
}

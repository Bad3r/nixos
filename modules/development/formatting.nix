{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        biome
        shfmt
        nixfmt-rfc-style
        treefmt
      ];
    };
}

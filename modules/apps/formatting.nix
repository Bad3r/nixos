{
  flake.nixosModules.apps.formatting =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        biome
        shfmt
        nixfmt-rfc-style
        treefmt
      ];
    };

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

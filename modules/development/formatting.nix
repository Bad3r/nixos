{
  flake.modules.nixos.workstation =
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

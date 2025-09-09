{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        marktext
        glow # Terminal-based markdown renderer
      ];
    };
}

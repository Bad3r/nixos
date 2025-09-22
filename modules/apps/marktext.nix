{
  flake.nixosModules.apps.marktext =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        marktext
        glow
      ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        marktext
        glow
      ];
    };
}

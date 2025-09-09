{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        localsend
      ];
    };
}

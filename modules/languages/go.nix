{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = with pkgs; [
        go
      ];
    };
}

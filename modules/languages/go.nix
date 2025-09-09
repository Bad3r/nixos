{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        go
      ];
    };
}

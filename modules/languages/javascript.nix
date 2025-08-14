{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        nodejs_22
        nodejs_24
        yarn
      ];
    };
}

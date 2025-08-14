{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        httpx
        curlie
        tor
      ];
    };
}

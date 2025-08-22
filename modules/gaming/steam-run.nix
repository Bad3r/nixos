{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # "steam"
        # "steam-run"
        # "steam-unwrapped"
      ];
      programs.steam.enable = false;
    };
}

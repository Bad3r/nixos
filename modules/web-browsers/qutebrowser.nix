{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # qutebrowser  # Temporarily disabled: Python 3.13 compatibility issue with lxml-html-clean
      ];
    };
}

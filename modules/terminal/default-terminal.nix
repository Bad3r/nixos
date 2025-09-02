_: {
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      # Install kitty system-wide
      environment.systemPackages = [ pkgs.kitty ];

      # Set kitty as the default terminal
      environment.variables = {
        TERMINAL = "kitty";
      };

      # Configure XDG mime associations for terminal
      xdg.mime.defaultApplications = {
        "application/x-terminal-emulator" = "kitty.desktop";
        "x-scheme-handler/terminal" = "kitty.desktop";
      };
    };
}

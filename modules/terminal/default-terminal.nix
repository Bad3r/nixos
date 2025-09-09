_: {
  flake.modules.nixos.pc =
    { pkgs, lib, ... }:
    {
      # Install kitty early in the list so later roles/users can override
      environment.systemPackages = lib.mkBefore [ pkgs.kitty ];

      # Set kitty as the default terminal unless overridden later
      environment.variables.TERMINAL = lib.mkDefault "kitty";

      # Configure XDG mime associations for terminal (can be overridden later)
      xdg.mime.defaultApplications = {
        "application/x-terminal-emulator" = lib.mkDefault "kitty.desktop";
        "x-scheme-handler/terminal" = lib.mkDefault "kitty.desktop";
      };
    };
}

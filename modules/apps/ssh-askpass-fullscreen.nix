{
  flake.nixosModules.apps.ssh-askpass-fullscreen =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ssh-askpass-fullscreen ];

      programs.ssh = {
        enableAskPassword = true;
        askPassword = lib.getExe pkgs.ssh-askpass-fullscreen;
      };

      environment.variables.SSH_ASKPASS_REQUIRE = lib.mkDefault "force";

      security.sudo.extraConfig = lib.mkAfter ''
        Defaults env_keep += "SSH_ASKPASS SSH_ASKPASS_REQUIRE DISPLAY WAYLAND_DISPLAY XAUTHORITY"
      '';
      security.sudo-rs.extraConfig = lib.mkAfter ''
        Defaults env_keep += "SSH_ASKPASS SSH_ASKPASS_REQUIRE DISPLAY WAYLAND_DISPLAY XAUTHORITY"
      '';
    };

  flake.nixosModules.base =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ssh-askpass-fullscreen ];

      programs.ssh = {
        enableAskPassword = true;
        askPassword = lib.getExe pkgs.ssh-askpass-fullscreen;
      };

      environment.variables.SSH_ASKPASS_REQUIRE = lib.mkDefault "force";

      security.sudo.extraConfig = lib.mkAfter ''
        Defaults env_keep += "SSH_ASKPASS SSH_ASKPASS_REQUIRE DISPLAY WAYLAND_DISPLAY XAUTHORITY"
      '';
      security.sudo-rs.extraConfig = lib.mkAfter ''
        Defaults env_keep += "SSH_ASKPASS SSH_ASKPASS_REQUIRE DISPLAY WAYLAND_DISPLAY XAUTHORITY"
      '';
    };
}

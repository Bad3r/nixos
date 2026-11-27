/*
  Package: atuin
  Description: Encrypted, synchronized shell history manager with powerful search.
  Homepage: https://atuin.sh/
*/

_: {
  flake.homeManagerModules.apps.atuin =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "atuin" "extended" "enable" ] false osConfig;
      unreachable = "http://127.0.0.1:1";
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.atuin = {
          enable = true;
          package = lib.attrByPath [ "programs" "atuin" "extended" "package" ] pkgs.atuin osConfig;
          # The arrows stay on zsh's prefix history search (modules/shell/zsh/keybindings.nix).
          flags = [ "--disable-up-arrow" ];
          # Socket-activated systemd user service; output capture stores through it.
          daemon.enable = true;
          settings = {
            # Only atuin's first-run config file sets this, and Home Manager replaces that file.
            enter_accept = true;
            ai = {
              # Unbinds `?` and turns off the Atuin Hub chat.
              enabled = false;
              endpoint = unreachable;
            };
            auto_sync = false;
            # An unreachable server blocks manual sync and the daemon's startup capabilities request.
            sync_address = unreachable;
            # Hub protocol makes account linking and `atuin setup` use sync_address instead of hub.atuin.sh.
            sync_protocol = "hub";
            pty_proxy.enabled = true;
            output.enabled = true;
          };
        };

        # Home Manager renders `atuin init nu` at build time, without this config, so it never starts pty-proxy.
        programs.nushell.extraConfig = lib.mkIf config.programs.atuin.enableNushellIntegration (
          lib.mkOrder 1990 ''
            source ${
              pkgs.runCommand "atuin-pty-proxy-init.nu" { nativeBuildInputs = [ pkgs.writableTmpDirAsHomeHook ]; }
                ''
                  ${lib.getExe config.programs.atuin.package} pty-proxy init nu > "$out"
                ''
            }
          ''
        );

        # PowerShell has no Home Manager module; atuin renders its init at shell start, with this config.
        xdg.configFile."powershell/Microsoft.PowerShell_profile.ps1" =
          lib.mkIf (lib.attrByPath [ "programs" "powershell" "extended" "enable" ] false osConfig)
            {
              text = ''
                & '${lib.getExe config.programs.atuin.package}' init powershell ${lib.escapeShellArgs config.programs.atuin.flags} | Out-String | Invoke-Expression
              '';
            };

        # No AF_INET/AF_INET6 sockets; the activation socket and unix clients still work.
        systemd.user.services.atuin-daemon.Service.RestrictAddressFamilies = [ "AF_UNIX" ];
      };
    };
}

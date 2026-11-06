# i3 workspace assignments and named per-window rules.
{ config, ... }:
let
  inherit (config.flake.lib) octicons;
in
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      cfg = config.gui.i3;
      workspaceName = octicons.nameOf;
      claudeDesktopEnabled = lib.attrByPath [
        "programs"
        "claude-desktop"
        "extended"
        "enable"
      ] false osConfig;
      rustdeskEnabled =
        lib.attrByPath [ "programs" "rustdesk" "extended" "enable" ] false osConfig
        && lib.attrByPath [ "systemd" "services" "rustdesk" "enable" ] false osConfig;
      # Quarter-screen geometry calculations (all derived from config options)
      # Width:  screenWidth/2 - borderWidth*2  (gap on both sides of center split)
      # Height: screenHeight/2 - fontSize*2 - 1  (account for bar area)
      # X:      screenWidth/2 + borderWidth  (start just past center)
      # Y:      barHeight  (start below status bar)
      qWidth = toString ((cfg.screenWidth / 2) - (cfg.borderWidth * 2));
      qHeight = toString ((cfg.screenHeight / 2) - (cfg.fontSize * 2) - 1);
      xPos = toString ((cfg.screenWidth / 2) + cfg.borderWidth);
      yPos = toString cfg.barHeight;

      topRight = "resize set ${qWidth} px ${qHeight} px, move position ${xPos} px ${yPos} px";
      onePassword = "resize set 949 px 765 px, move position center";
      protonvpnX = toString (cfg.screenWidth - 408 - (cfg.borderWidth * 2) - 1);
      nativeRules = lib.filterAttrs (
        _: rule: rule.enable && rule.condition && rule.processArgs == [ ]
      ) cfg.windowRules;
      orderedRules = lib.sort (a: b: a.order < b.order) (lib.mapAttrsToList (_: rule: rule) nativeRules);
    in
    {
      options.gui.i3.windowRules = lib.mkOption {
        default = { };
        description = ''
          Named i3 window rules, sorted by order, then name, after default styling.
          Rules with processArgs are handled by the process-aware window-rule service.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to apply this window rule.";
              };
              condition = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Host prerequisites for applying this rule, independent of the enable preference.";
              };
              criteria = lib.mkOption {
                type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.bool);
                description = "i3 criteria that must all match the window.";
              };
              command = lib.mkOption {
                type = lib.types.str;
                default = "floating enable";
                description = "i3 command to run for matching windows.";
              };
              processArgs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Exact arguments that must also occur in the window owner's command line.";
              };
              order = lib.mkOption {
                type = lib.types.int;
                default = 1000;
                description = "Execution order within native or process rules; lower values run first.";
              };
            };
          }
        );
      };

      config = lib.mkIf config.xsession.windowManager.i3.enable {
        gui.i3.windowRules =
          lib.mapAttrs
            (
              _:
              lib.mapAttrs (
                key: value:
                if key == "criteria" then
                  lib.mapAttrs (_: lib.mkDefault) value
                else if key == "condition" then
                  value
                else
                  lib.mkDefault value
              )
            )
            {
              bitwarden = {
                criteria.class = "(?i)^bitwarden$";
                command = "floating enable, ${topRight}";
              };
              bitwarden-extension = {
                criteria = {
                  window_type = "dialog";
                  title = "(?i)Extension:.*Bitwarden";
                };
                command = topRight;
              };
              calendar = {
                # gsimplecal owns placement through mainwindow_position and mainwindow_yoffset.
                criteria.class = "(?i)^gsimplecal$";
                command = "floating enable, border none";
              };
              claude-desktop = {
                condition = claudeDesktopEnabled;
                criteria.class = "(?i)^com\\.anthropic\\.claude$";
                command = "floating enable, border none, ${topRight}";
              };
              devtools = {
                criteria.class = "(?i)^devtools$";
                command = "floating enable, ${topRight}";
              };
              dialog = {
                order = 900;
                criteria.window_type = "dialog";
                command = "floating enable, focus";
              };
              one-password = {
                criteria.class = "(?i)^1password$";
                command = "floating enable, ${onePassword}";
              };
              popup = {
                order = 900;
                criteria.window_role = "(?i)^pop-?up$";
              };
              protonvpn = {
                criteria.class = "(?i)^protonvpn-app$";
                command = "floating enable, move position ${protonvpnX} px ${yPos} px";
              };
              rustdesk-connection-manager = {
                condition = rustdeskEnabled;
                criteria = {
                  class = "(?i)^rustdesk$";
                  instance = "(?i)^rustdesk$";
                };
                # Titles overlap other RustDesk windows; only the incoming manager runs --cm.
                processArgs = [ "--cm" ];
              };
              settings-dialog = {
                criteria.class = "(?i)^(?:qt5ct|pinentry)$";
                command = "floating enable, focus";
              };
              toolbox = {
                order = 900;
                criteria.window_role = "(?i)^toolbox$";
              };
              utility = {
                order = 900;
                criteria.window_type = "utility";
              };
              volume-control = {
                criteria.class = "(?i)^pwvucontrol$";
                command = "floating enable, ${topRight}";
              };
            };

        xsession.windowManager.i3.config = {
          assigns = lib.mkOptionDefault {
            "number \"${workspaceName 2}\"" = [ { class = "(?i)^${cfg.browserClass}$"; } ];
          };
          window.commands = [
            {
              criteria.urgent = "latest";
              command = "focus";
            }
            {
              # Named rules follow so borderless exceptions override this default.
              criteria.all = true;
              command = ''border pixel ${toString cfg.borderWidth}, title_format "<b>%title</b>", title_window_icon padding 3px'';
            }
          ]
          ++ map (rule: { inherit (rule) criteria command; }) orderedRules;
        };
      };
    };
}

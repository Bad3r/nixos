{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      rules = lib.filterAttrs (
        _: rule: rule.enable && rule.condition && rule.processArgs != [ ]
      ) config.gui.i3.windowRules;
      # Let i3 interpret its own PCRE criteria, including boolean selectors.
      criteriaString =
        criteria:
        lib.concatStringsSep " " (
          lib.mapAttrsToList (
            key: value: if builtins.isBool value then lib.optionalString value key else ''${key}="${value}"''
          ) criteria
        );
      rulesFile = pkgs.writeText "i3-process-window-rules.json" (
        builtins.toJSON (
          map
            (rule: {
              inherit (rule) name command processArgs;
              criteria = criteriaString rule.criteria;
            })
            (
              lib.sort (a: b: a.order < b.order) (
                lib.mapAttrsToList (
                  name: rule:
                  rule
                  // {
                    inherit name;
                  }
                ) rules
              )
            )
        )
      );
      python = pkgs.python3.withPackages (ps: [
        ps.i3ipc
        ps.python-xlib
      ]);
    in
    {
      config = lib.mkIf (config.xsession.windowManager.i3.enable && rules != { }) {
        systemd.user.services.i3-process-window-rules = {
          Unit = {
            Description = "i3 window rules with process argument filters";
            After = [ "i3-session.target" ];
            PartOf = [ "i3-session.target" ];
          };
          Install.WantedBy = [ "i3-session.target" ];
          Service = {
            ExecStart = "${python}/bin/python3 ${./_process-window-rules.py} ${rulesFile}";
            # i3 restarts close IPC connections; rescan when reconnecting.
            Restart = "always";
            RestartSec = 2;
          };
        };
      };
    };
}

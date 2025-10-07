{ lib, ... }:
{
  flake.lib.security.usbguard =
    let
      baseRules = ''
        # Allow USB hubs so topology can enumerate
        allow with-interface equals { 09:*:* }

        # Allow Human Interface Devices (keyboards, mice, digitizers)
        allow with-interface equals { 03:00:* }
        allow with-interface equals { 03:01:* }
        allow with-interface equals { 03:02:* }
      '';

      defaultAuditRules = [
        "-w /var/lib/usbguard/rules.conf -p wa -k usbguard-policy"
        "-w /var/lib/usbguard/IPCAccessControl.d -p wa -k usbguard-ipc"
        "-w /etc/usbguard -p wa -k usbguard-config"
        "-w /run/current-system/sw/bin/usbguard -p x -k usbguard-cli"
        "-w /run/current-system/sw/bin/usbguard-daemon -p x -k usbguard-daemon"
      ];

      defaultPrometheusRuleText = ''
        groups:
          - name: usbguard
            rules:
              - alert: USBGuardServiceDown
                expr: node_systemd_unit_state{systemd_unit="usbguard.service",state="failed"} == 1
                for: 2m
                labels:
                  severity: critical
                annotations:
                  summary: "USBGuard daemon stopped"
                  description: "USBGuard enforcement is not running on {{ $labels.instance }}."
              - alert: USBGuardServiceRestarted
                expr: increase(node_systemd_unit_restart_count_total{systemd_unit=\"usbguard.service\"}[15m]) > 0
                for: 0m
                labels:
                  severity: warning
                annotations:
                  summary: "USBGuard restarted in the last 15 minutes"
                  description: "USBGuard restarted recently on {{ $labels.instance }}; inspect audit logs for policy violations."
      '';
    in
    {
      inherit baseRules defaultAuditRules defaultPrometheusRuleText;

      mkGrafanaDashboard =
        {
          datasourceUid,
          dashboardUid,
        }:
        builtins.toJSON {
          __inputs = { };
          annotations = {
            list = [
              {
                builtIn = 1;
                datasource = "-- Grafana --";
                enable = true;
                hide = false;
                iconColor = "rgba(0, 211, 255, 1)";
                name = "Annotations & Alerts";
                type = "dashboard";
              }
            ];
          };
          editable = true;
          fiscalYearStartMonth = 0;
          graphTooltip = 1;
          id = null;
          iteration = 1717603200000;
          links = [ ];
          liveNow = false;
          panels = [
            {
              datasource = {
                type = "prometheus";
                uid = datasourceUid;
              };
              fieldConfig = {
                defaults = {
                  color = {
                    mode = "thresholds";
                  };
                  mappings = [
                    {
                      options = {
                        "0" = {
                          color = "green";
                          index = 0;
                          text = "Running";
                        };
                        "1" = {
                          color = "red";
                          index = 1;
                          text = "Failed";
                        };
                      };
                      type = "value";
                    }
                  ];
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      {
                        color = "green";
                        value = null;
                      }
                      {
                        color = "red";
                        value = 1;
                      }
                    ];
                  };
                  unit = "none";
                };
                overrides = [ ];
              };
              gridPos = {
                h = 6;
                w = 8;
                x = 0;
                y = 0;
              };
              id = 1;
              options = {
                colorMode = "value";
                graphMode = "area";
                justifyMode = "auto";
                orientation = "horizontal";
                reduceOptions = {
                  calcs = [ "lastNotNull" ];
                  fields = "";
                  values = false;
                };
                text = { };
              };
              pluginVersion = "10.2.3";
              targets = [
                {
                  datasource = {
                    type = "prometheus";
                    uid = datasourceUid;
                  };
                  expr = "max(node_systemd_unit_state{systemd_unit=\"usbguard.service\",state=\"failed\"})";
                  format = "time_series";
                  legendFormat = "State";
                  range = true;
                  refId = "A";
                }
              ];
              title = "USBGuard Service State";
              type = "stat";
            }
            {
              datasource = {
                type = "prometheus";
                uid = datasourceUid;
              };
              fieldConfig = {
                defaults = {
                  unit = "short";
                };
                overrides = [ ];
              };
              gridPos = {
                h = 8;
                w = 16;
                x = 8;
                y = 0;
              };
              id = 2;
              options = {
                legend = {
                  calcs = [ "sum" ];
                  displayMode = "table";
                  placement = "right";
                  showLegend = true;
                };
                tooltip = {
                  mode = "single";
                  sort = "none";
                };
              };
              targets = [
                {
                  datasource = {
                    type = "prometheus";
                    uid = datasourceUid;
                  };
                  expr = "increase(node_systemd_unit_restart_count_total{systemd_unit=\"usbguard.service\"}[1h])";
                  refId = "A";
                }
                {
                  datasource = {
                    type = "prometheus";
                    uid = datasourceUid;
                  };
                  expr = "increase(node_systemd_unit_state{systemd_unit=\"usbguard.service\",state=\"activating\"}[1h])";
                  refId = "B";
                }
              ];
              title = "USBGuard Activity (1h)";
              type = "timeseries";
            }
          ];
          refresh = "1m";
          schemaVersion = 38;
          style = "dark";
          tags = [
            "usbguard"
            "security"
          ];
          templating = {
            list = [ ];
          };
          time = {
            from = "now-6h";
            to = "now";
          };
          timepicker = { };
          timezone = "";
          title = "USBGuard Overview";
          uid = dashboardUid;
          version = 1;
          weekStart = "";
        };

      mkRules =
        extraRules:
        let
          extraList =
            if extraRules == null then
              [ ]
            else if builtins.isList extraRules then
              extraRules
            else
              [ extraRules ];
          ruleset = [
            (lib.strings.trim baseRules)
          ]
          ++ lib.filter (rule: rule != "") (map lib.strings.trim extraList);
        in
        lib.concatStringsSep "\n\n" ruleset;
    };
}

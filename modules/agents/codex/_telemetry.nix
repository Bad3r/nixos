# Local Codex telemetry with content filtering before file export.
{
  pkgs,
  # Off until nixpkgs ships a working otelcol-contrib: 0.155 fails to build on Go 1.27,
  # 0.164 panics at startup (open-telemetry/opentelemetry-collector-contrib#51868).
  enabled ? false,
}:
let
  # Avoid the default OTLP port used by other local collectors.
  address = "127.0.0.1:14318";

  exporter = signal: {
    otlp-http = {
      endpoint = "http://${address}/v1/${signal}";
      protocol = "binary";
    };
  };

  signals = [
    "metrics"
    "logs"
    "traces"
  ];

  fileExporter = signal: {
    name = "file/${signal}";
    value = {
      path = "\${env:STATE_DIRECTORY}/${signal}.jsonl";
      rotation = {
        max_megabytes = 100;
        max_backups = 10;
      };
    };
  };

  collectorConfig = {
    receivers.otlp.protocols.http.endpoint = address;
    exporters = builtins.listToAttrs (map fileExporter signals);
    # Tool payloads can contain prompts and subagent replies even with content logging off.
    processors."attributes/strip-content".actions =
      map
        (key: {
          inherit key;
          action = "delete";
        })
        [
          "arguments"
          "output"
        ];
    service = {
      # Avoid exposing internal metrics on a separate listener.
      telemetry.metrics.level = "none";
      pipelines = builtins.listToAttrs (
        map (signal: {
          name = signal;
          value = {
            receivers = [ "otlp" ];
            processors = if signal == "logs" then [ "attributes/strip-content" ] else [ ];
            exporters = [ "file/${signal}" ];
          };
        }) signals
      );
    };
  };
in
{
  inherit enabled;

  codexOtel =
    if enabled then
      {
        exporter = exporter "logs";
        trace_exporter = exporter "traces";
        metrics_exporter = exporter "metrics";
      }
    else
      {
        exporter = "none";
        trace_exporter = "none";
        metrics_exporter = "none";
      };

  collectorConfigFile =
    (pkgs.formats.yaml { }).generate "codex-telemetry-otelcol.yaml"
      collectorConfig;
}

/*
  Local OpenTelemetry capture for Codex: the exporter settings merged into
  config.toml and the collector configuration run by the codex-telemetry user
  service (home.nix). The collector writes each signal as OTLP JSON lines under
  the unit's StateDirectory.

  Source: openai/codex 0.166.0, codex-rs/config/src/types.rs (OtelExporterKind).
*/
{ pkgs }:
let
  # Loopback only; a non-default port keeps other OTLP tools from writing here.
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
      # The live file plus max_backups bound each signal's disk use; rotation deletes the oldest.
      rotation = {
        max_megabytes = 100;
        max_backups = 10;
      };
    };
  };

  collectorConfig = {
    receivers.otlp.protocols.http.endpoint = address;
    exporters = builtins.listToAttrs (map fileExporter signals);
    service = {
      # The default internal telemetry opens a Prometheus listener.
      telemetry.metrics.level = "none";
      pipelines = builtins.listToAttrs (
        map (signal: {
          name = signal;
          value = {
            receivers = [ "otlp" ];
            exporters = [ "file/${signal}" ];
          };
        }) signals
      );
    };
  };
in
{
  codexOtel = {
    exporter = exporter "logs";
    trace_exporter = exporter "traces";
    metrics_exporter = exporter "metrics";
  };

  collectorConfigFile =
    (pkgs.formats.yaml { }).generate "codex-telemetry-otelcol.yaml"
      collectorConfig;
}

# Codex telemetry

Every Codex process exports its OpenTelemetry metrics, logs, and traces to a collector on loopback.
That covers interactive sessions, `codex exec`, and the shared background server.
The [telemetry helper](../../../modules/agents/codex/_telemetry.nix) sets the exporter endpoints and the collector configuration.
The [Home Manager module](../../../modules/agents/codex/home.nix) runs the collector as the `codex-telemetry` user service.

Analytics events, feedback uploads, and the built-in Statsig metrics upload stay off in the [site policy](../../../modules/agents/codex/_settings.nix).
Prompt text, agent responses, and Guardian assessments are not logged.

## Files

The collector writes one file per signal to `$XDG_STATE_HOME/codex-telemetry` (normally `~/.local/state/codex-telemetry`).
The directory is readable only by its owner.

- `metrics.jsonl`, `logs.jsonl`, and `traces.jsonl` hold one OTLP JSON export request per line.
- A full file is renamed with a timestamp and a `-size` suffix, and the oldest renamed file is deleted past the backup limit.
- The glob `logs*.jsonl` reads the renamed files first and the live file last.

## Captured content

- Metrics: turn latency, token usage, tool calls, startup phases, and storage counters, tagged with model, auth mode, originator, and version.
- Logs: one record per event, such as conversation starts, API requests, stream events, tool decisions, and tool results.
- Log records carry the conversation ID, host name, approval and sandbox policy, and token counts.
- A tool result record holds the call's arguments and the start of its output, capped by `otel.tool_result.max_bytes`.
- A user prompt record holds `[REDACTED]` and the prompt length.
- Traces: spans for each turn down to individual file reads, with token usage attributes.
- The `codex.turn.cost_microusd` metric and `codex.turn_cost` log event report a finished turn's estimated cost, fetched as described under caveats.

## Read the files

Run these from `~/.local/state/codex-telemetry`.
Count metric names:

```sh
jq -r '.resourceMetrics[].scopeMetrics[].metrics[].name' metrics*.jsonl | sort | uniq -c
```

Flatten log records to their attributes and select one event:

```sh
jq -c '.resourceLogs[].scopeLogs[].logRecords[]
  | (.attributes // []) | map({(.key): (.value | to_entries[0].value)}) | add
  | select(."event.name" == "codex.api_request")' logs*.jsonl
```

List the slowest spans:

```sh
jq -r '.resourceSpans[].scopeSpans[].spans[]
  | "\(((.endTimeUnixNano | tonumber) - (.startTimeUnixNano | tonumber)) / 1e6 | floor) ms \(.name)"' \
  traces*.jsonl | sort -rn | head
```

Inspect the collector:

```sh
systemctl --user status codex-telemetry
journalctl --user -u codex-telemetry
```

## Apply a change

Home Manager starts or restarts the service on switch.
Each Codex process reads the exporters when it starts, so a new launch picks up a change.
The background server keeps its startup configuration; restart it, which interrupts the sessions attached to it:

```sh
codex app-server daemon restart
```

## Caveats

- An OTLP log or metrics exporter starts Codex's turn-cost worker in every interactive session, `codex exec` run, and background server.
- At startup the worker sends OpenAI one query with a random turn ID to test the cost endpoint.
- After that it sends the thread and turn IDs of finished turns, authenticated as the signed-in account, until each is priced or dropped.
- ChatGPT sign-in sends those queries to the usage estimates endpoint under `chatgpt_base_url`; an API key sends them to the turn-costs endpoint.
- No setting turns the worker off while those exporters are configured; only Amazon Bedrock providers skip it.
- Explicit exporters ignore `analytics.enabled`, which still blocks the Statsig upload and analytics events.
- Without the collector, Codex runs normally and drops the signals; `codex exec` prints `opentelemetry_sdk` export errors on stderr.
- Any local process can send data to the loopback receiver and so write into these files.

[OpenTelemetry Collector file exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter)

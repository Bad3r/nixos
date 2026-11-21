/*
  Optional Codex process environment, exported by the launch wrapper and Home
  Manager login sessions. CODEX_HOME is computed by home.nix and the
  wrapper; shell_environment_policy in _settings.nix controls tool subprocesses.
  $CODEX_HOME/.env cannot set CODEX_* keys (arg0/src/lib.rs), so they belong here.

  Source: Bad3r/codex main b1573f102413e96a6481087922bf425231222dee.
  Reader paths below are relative to codex-rs/. Values here enter the Nix store;
  provide credentials through the runtime environment or Codex login instead.
*/
{
  vars = {
    # Storage: state/src/lib.rs and core/src/config/mod.rs.
    # Used when sqlite_home is unset; an exact managed requirement takes priority.
    # CODEX_SQLITE_HOME = "/absolute/path/state";

    # TLS: http-client/src/custom_ca.rs. CODEX_CA_CERTIFICATE takes precedence
    # over SSL_CERT_FILE; both select a PEM bundle for Codex HTTP clients.
    # CODEX_CA_CERTIFICATE = "/absolute/path/ca-bundle.pem";
    # SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    # SSL_CERT_FILE and SSL_CERT_DIR also replace the platform root store for
    # native-roots clients (rustls-native-certs); http-client/src/native_roots.rs
    # rereads the roots for each client while either is set.
    # SSL_CERT_DIR = "/etc/ssl/certs";

    # OpenAI request headers: model-provider-info/src/lib.rs.
    # OPENAI_ORGANIZATION = "";
    # OPENAI_PROJECT = "";

    # Local OSS providers (ollama, lmstudio): model-provider-info/src/lib.rs.
    # CODEX_OSS_BASE_URL wins; CODEX_OSS_PORT only replaces the localhost port.
    # CODEX_OSS_BASE_URL = "http://localhost:11434/v1";
    # CODEX_OSS_PORT = "11434";

    # Remote execution: exec-server/src/environment_provider.rs. A ws:// or wss://
    # URL replaces the local environment; "none" disables shell and file tools.
    # CODEX_EXEC_SERVER_URL = "ws://127.0.0.1:8765";

    # Extra comma-separated `git -c` pairs for patch apply: git-utils/src/apply.rs.
    # CODEX_APPLY_GIT_CFG = "core.autocrlf=false";

    # TUI: tui/src/tui/keyboard_modes.rs. A boolean forces keyboard enhancement
    # off (true) or on (false); unset detects VS Code under WSL.
    # CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT = "1";
    # Session recording: tui/src/session_log.rs. The path defaults to
    # log_dir/session-<timestamp>.jsonl.
    # CODEX_TUI_RECORD_SESSION = "1";
    # CODEX_TUI_SESSION_LOG_PATH = "/absolute/path/session.jsonl";

    # Cloud tasks (`codex cloud`): cloud-tasks/src/lib.rs. Only HTTPS on port 443 at
    # chatgpt.com, chat.openai.com, or chatgpt-staging.com is accepted.
    # CODEX_CLOUD_TASKS_BASE_URL = "https://chatgpt.com/backend-api";
    # Cloud tasks overlay borders: cloud-tasks/src/ui.rs. "1" or unset is rounded,
    # anything else square.
    # CODEX_TUI_ROUNDED = "0";

    # Rollout trace bundles, one per root session: rollout-trace/src/thread.rs.
    # CODEX_ROLLOUT_TRACE_ROOT = "/absolute/path/traces";

    # OTLP exporters: otel/src/otlp.rs, otel/src/provider.rs, and
    # otel/src/metrics/client.rs. Timeouts are milliseconds; per-signal values
    # win over OTEL_EXPORTER_OTLP_TIMEOUT. Temporality applies to OTLP metrics
    # only: cumulative | lowmemory, otherwise delta.
    # OTEL_EXPORTER_OTLP_TIMEOUT = "10000";
    # OTEL_EXPORTER_OTLP_LOGS_TIMEOUT = "10000";
    # OTEL_EXPORTER_OTLP_TRACES_TIMEOUT = "10000";
    # OTEL_EXPORTER_OTLP_METRICS_TIMEOUT = "10000";
    # OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";

    # Tracing: app-server/src/lib.rs, exec/src/lib.rs, and
    # tui/src/startup_orchestration.rs.
    # RUST_LOG uses tracing_subscriber's directive syntax.
    # RUST_LOG = "warn,codex_core=info";
    # LOG_FORMAT selects app-server stderr formatting.
    # LOG_FORMAT = "json";
    # Rust standard library panic diagnostics; this does not enable request tracing.
    # RUST_BACKTRACE = "1";
  };
}

/*
  Optional Codex process environment, exported by the launch wrapper and Home
  Manager login sessions. CODEX_HOME is computed by home-manager.nix and the
  wrapper; shell_environment_policy in _settings.nix controls tool subprocesses.

  Source: openai/codex 58670eeac4b0bdb9fcb86929d8631c14aee0d9f6.
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

    # OpenAI request headers: model-provider-info/src/lib.rs.
    # OPENAI_ORGANIZATION = "";
    # OPENAI_PROJECT = "";

    # Tracing: app-server/src/lib.rs and exec/src/lib.rs.
    # RUST_LOG uses tracing_subscriber's directive syntax.
    # RUST_LOG = "warn,codex_core=info";
    # LOG_FORMAT selects app-server stderr formatting.
    # LOG_FORMAT = "json";
    # Rust panic diagnostics; this does not enable request tracing.
    # RUST_BACKTRACE = "1";
  };
}

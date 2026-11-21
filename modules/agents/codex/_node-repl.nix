{
  command,
  configDir,
  profileDirectory,
  version,
}:
let
  bin = builtins.dirOf command;
  modules = "${builtins.dirOf bin}/lib/node_modules";
in
{
  # The desktop process supplies the identity and pipe for the current session.
  env_vars = [
    "BROWSER_USE_ACCESS_EXECUTOR_ID"
    "BROWSER_USE_ACCESS_PIPE_PATH"
    "BROWSER_USE_ACCESS_VERIFYING_IDENTITY"
  ];
  env = {
    BROWSER_USE_AVAILABLE_BACKENDS = "chrome,iab,mcpapps";
    BROWSER_USE_CODEX_APP_BUILD_FLAVOR = "prod";
    BROWSER_USE_CODEX_APP_VERSION = version;
    BROWSER_USE_TINYSKY_ENABLED = "1";
    CODEX_CLI_PATH = "${profileDirectory}/bin/codex";
    CODEX_HOME = configDir;
    # The desktop app's lazyTrustedWorker feature flag, off by default.
    NODE_REPL_LAZY_TRUSTED_WORKER = "0";
    NODE_REPL_INSTRUCTIONS_USE_CASE_BROWSER = "";
    NODE_REPL_INSTRUCTIONS_USE_CASE_CHROME = "";
    NODE_REPL_NATIVE_PIPE_CONNECT_TIMEOUT_MS = "1000";
    NODE_REPL_NODE_MODULE_DIRS = modules;
    NODE_REPL_NODE_PATH = "${bin}/node";
    NODE_REPL_TRUSTED_CODE_PATHS = "${configDir}:${modules}";
    NODE_REPL_TRUSTED_SERVICES = builtins.toJSON {
      browser = "${configDir}/plugins/cache/openai-bundled/browser/${version}/scripts/browser-service.mjs";
    };
  };
}

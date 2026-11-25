# Shared local mitmproxy configuration and wrapper snippets for Antigravity CLI and Hub.
let
  defaultPort = 18092;
  defaultTemplatesDir = ./templates;
  defaultGuidelinesPin = ./_server-guidelines.sha256;
  addonScript = ./_proxy_overrides.py;

  # Intercept only the Google endpoints that proxy_overrides.py rewrites; all
  # other hosts pass through mitmdump as untouched TLS tunnels.
  allowHostsRegex = "^(daily-cloudcode-pa|cloudcode-pa|aicode)\\.googleapis\\.com(:443)?$";

  proxyEnvVars = [
    "HTTPS_PROXY"
    "HTTP_PROXY"
    "https_proxy"
    "http_proxy"
    "NO_PROXY"
    "no_proxy"
    "SSL_CERT_FILE"
    "NODE_EXTRA_CA_CERTS"
  ];

  # Hub language_server also pins TEMPLATE_DATA_DIR across Electron's login-shell env merge.
  hubPinVars = [ "TEMPLATE_DATA_DIR" ] ++ proxyEnvVars;

  mkProxyOptions =
    { lib, pkgs }:
    {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to run the local `antigravity-proxy` user systemd service and
          route Antigravity CLI and Hub API traffic through it.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = defaultPort;
        description = "Loopback port on 127.0.0.1 for the local `antigravity-proxy` service.";
      };

      guidelinesOverride = lib.mkOption {
        type = lib.types.nullOr (lib.types.either (lib.types.enum [ "strip" ]) lib.types.path);
        default = "strip";
        description = ''
          How to handle server-pushed `template__system_prompts__guidelines` in
          `fetchAvailableModels`: `"strip"` deletes it so local
          `templates/system_prompts/guidelines.tmpl` applies, a path replaces
          its content directly, and `null` leaves it untouched. `guidelinesPin`
          applies in every mode.
        '';
      };

      guidelinesPin = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = defaultGuidelinesPin;
        description = ''
          File whose first field is the expected SHA-256 of Google's server
          guidelines template. When set, drift or a failed check returns HTTP 502.
          Drifted templates are saved under
          `$XDG_STATE_HOME/antigravity-proxy/drift/`.
        '';
      };

      flagOverrides = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.bool
            lib.types.int
            lib.types.float
            lib.types.str
          ]
        );
        default = { };
        example = {
          "generic-system-prompt" = false;
          "enable-programmatic-tools" = true;
        };
        description = ''
          Mendel experiment flag overrides rewritten in `fetchConfig` and
          `listExperiments`. The Nix value type selects the proto field (`bool`,
          `int`, `float`, or `str` value), except that a flag the server sends
          as `stringValue` stays a string.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.mitmproxy;
        defaultText = lib.literalExpression "pkgs.mitmproxy";
        description = "Mitmproxy package used by `antigravity-proxy.service`.";
      };
    };

  mkProxyStartScript =
    {
      lib,
      pkgs,
      proxy,
      systemCaBundle ? "/etc/ssl/certs/ca-certificates.crt",
    }:
    let
      guidelinesOverrideStr =
        if proxy.guidelinesOverride == null then "" else "${proxy.guidelinesOverride}";
      guidelinesPinStr = if proxy.guidelinesPin == null then "" else "${proxy.guidelinesPin}";
    in
    pkgs.writeShellScript "antigravity-proxy" ''
      set -euo pipefail
      state_dir="''${STATE_DIRECTORY:-''${XDG_STATE_HOME:-$HOME/.local/state}/antigravity-proxy}"
      mkdir -p -m 700 "$state_dir" "$state_dir/ca" "$state_dir/drift"
      exec ${proxy.package}/bin/mitmdump \
        --set flow_detail=0 \
        --set "confdir=$state_dir/ca" \
        --listen-host 127.0.0.1 \
        --listen-port ${toString proxy.port} \
        --set ${lib.escapeShellArg "allow_hosts=${allowHostsRegex}"} \
        -s ${addonScript} \
        --set ${lib.escapeShellArg "flag_overrides=${builtins.toJSON proxy.flagOverrides}"} \
        --set ${lib.escapeShellArg "guidelines_override=${guidelinesOverrideStr}"} \
        --set ${lib.escapeShellArg "guidelines_pin=${guidelinesPinStr}"} \
        --set "guidelines_drift_dir=$state_dir/drift" \
        --set "ca_bundle_out=$state_dir/bundle.pem" \
        --set "spki_out=$state_dir/spki.txt" \
        --set ${lib.escapeShellArg "system_ca_bundle=${systemCaBundle}"}
    '';

  # Shell snippet injected into `agy` and `antigravity` wrappers.
  # Caller's original proxy/TLS variables are saved so `_shell.nix` can restore
  # them before running agent shell commands.
  mkWrapperEnvSnippet =
    {
      lib,
      templatesDir ? null,
      proxy ? null,
      isHub ? false,
      appName ? if isHub then "antigravity" else "agy",
      skipUtilitySubcommands ? !isHub,
    }:
    let
      proxyEnabled = proxy != null && (proxy.enable or false);
      varsList = lib.concatStringsSep " " proxyEnvVars;
      pinVarsList = lib.concatStringsSep " " hubPinVars;
      proxyBody = ''
        _agy_proxy_state="''${XDG_STATE_HOME:-$HOME/.local/state}/antigravity-proxy"
        _agy_bundle="$_agy_proxy_state/bundle.pem"
        _agy_ca_cert="$_agy_proxy_state/ca/mitmproxy-ca-cert.pem"
        ${lib.optionalString isHub ''_agy_spki_file="$_agy_proxy_state/spki.txt"''}
        if [ ! -r "$_agy_bundle" ] || [ ! -r "$_agy_ca_cert" ]${lib.optionalString isHub " || [ ! -r \"$_agy_spki_file\" ]"}; then
          echo "${appName}: antigravity-proxy CA artifacts missing under $_agy_proxy_state (check: systemctl --user status antigravity-proxy)" >&2
          exit 1
        fi
        ${lib.optionalString isHub ''
          _agy_spki=""
          read -r _agy_spki < "$_agy_spki_file" || true
          if [ -z "$_agy_spki" ]; then
            echo "${appName}: antigravity-proxy SPKI pin is empty at $_agy_spki_file" >&2
            exit 1
          fi
        ''}
        if [ "''${ANTIGRAVITY_PROXY_ACTIVE:-}" != "1" ]; then
          export ANTIGRAVITY_PROXY_ACTIVE=1
          for _agy_var in ${varsList}; do
            if [ -n "''${!_agy_var+x}" ]; then
              export "ANTIGRAVITY_ORIG_SET_''${_agy_var}=1"
              export "ANTIGRAVITY_ORIG_''${_agy_var}=''${!_agy_var}"
            else
              unset "ANTIGRAVITY_ORIG_SET_''${_agy_var}" "ANTIGRAVITY_ORIG_''${_agy_var}"
            fi
          done
        fi
        _agy_proxy="http://127.0.0.1:${toString proxy.port}"
        export HTTPS_PROXY="$_agy_proxy" HTTP_PROXY="$_agy_proxy" https_proxy="$_agy_proxy" http_proxy="$_agy_proxy"
        export NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1'
        export SSL_CERT_FILE="$_agy_bundle"
        export NODE_EXTRA_CA_CERTS="$_agy_ca_cert"
        ${lib.optionalString isHub ''
          for _agy_var in ${pinVarsList}; do
            if [ -n "''${!_agy_var+x}" ]; then
              export "ANTIGRAVITY_PIN_''${_agy_var}=''${!_agy_var}"
            fi
          done
          set -- --proxy-server="$_agy_proxy" --ignore-certificate-errors-spki-list="$_agy_spki" "$@"
        ''}
        unset _agy_proxy_state _agy_bundle _agy_ca_cert _agy_proxy _agy_var${lib.optionalString isHub " _agy_spki_file _agy_spki"}
      '';
      gatedProxyBody =
        if skipUtilitySubcommands then
          ''
            case "''${1:-}" in
              -h | --help | -help | --version | -version | help | changelog | install | update | plugin | plugins | agentapi | mcp | mic-serve) ;;
              *)
                ${proxyBody}
                ;;
            esac
          ''
        else
          proxyBody;
    in
    lib.concatStringsSep "\n" (
      lib.optional (templatesDir != null) ''
        export TEMPLATE_DATA_DIR="''${TEMPLATE_DATA_DIR:-${lib.escapeShellArg "${templatesDir}"}}"
      ''
      ++ lib.optional (templatesDir != null && isHub) ''
        export ANTIGRAVITY_PIN_TEMPLATE_DATA_DIR="$TEMPLATE_DATA_DIR"
      ''
      ++ lib.optional proxyEnabled gatedProxyBody
    );

  # Restores caller's pre-proxy environment inside `_shell.nix` (`run_command`).
  restoreShellEnvSnippet =
    lib:
    let
      varsList = lib.concatStringsSep " " proxyEnvVars;
      pinVarsList = lib.concatStringsSep " " hubPinVars;
    in
    ''
      if [ "''${ANTIGRAVITY_PROXY_ACTIVE:-}" = "1" ]; then
        for _agy_var in ${varsList}; do
          _agy_set="ANTIGRAVITY_ORIG_SET_''${_agy_var}"
          _agy_val="ANTIGRAVITY_ORIG_''${_agy_var}"
          if [ "''${!_agy_set:-}" = "1" ]; then
            export "$_agy_var=''${!_agy_val-}"
          else
            unset "$_agy_var"
          fi
          unset "$_agy_set" "$_agy_val"
        done
        unset ANTIGRAVITY_PROXY_ACTIVE _agy_var _agy_set _agy_val
      fi
      for _agy_pin in ${pinVarsList}; do
        unset "ANTIGRAVITY_PIN_''${_agy_pin}"
      done
      unset _agy_pin
    '';

  # Restores pinned proxy and template variables inside Hub's `language_server`
  # wrapper after Electron merges the login-shell environment over its own.
  restorePinnedEnvSnippet =
    lib:
    let
      pinVarsList = lib.concatStringsSep " " hubPinVars;
    in
    ''
      for _agy_var in ${pinVarsList}; do
        _agy_pin="ANTIGRAVITY_PIN_''${_agy_var}"
        if [ -n "''${!_agy_pin+x}" ]; then
          export "$_agy_var=''${!_agy_pin}"
          unset "$_agy_pin"
        fi
      done
      unset _agy_var _agy_pin
    '';
in
{
  inherit
    addonScript
    allowHostsRegex
    defaultGuidelinesPin
    defaultPort
    defaultTemplatesDir
    hubPinVars
    mkProxyOptions
    mkProxyStartScript
    mkWrapperEnvSnippet
    proxyEnvVars
    restorePinnedEnvSnippet
    restoreShellEnvSnippet
    ;
}

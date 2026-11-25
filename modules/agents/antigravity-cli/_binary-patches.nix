# Byte patches applied to the `agy` ELF at build time by _patch_agy.py, which
# is pinned by sha256 to known builds and checks every replaced byte, so an
# unknown `agy` release fails the build instead of shipping unpatched.
let
  patchSets = [
    # Options.EnvironmentConfig.DevMode = true in the in-process language
    # server: TEMPLATE_DATA_DIR overrides, SetMendelFlagOverrides, and
    # /debug/pprof plus /metrics on its loopback ports without a CSRF token.
    "devmode"
    # Options.DisableTelemetry = true for the language server (TUI, print
    # mode, --hub, acp) and for the CLI's own analytics recorder.
    "notelemetry"
    # The background updater takes its "disabled" return; without it the
    # updater ignores AGY_CLI_DISABLE_AUTO_UPDATE unless that is exactly "true".
    "noautoupdate"
    # Drops the file_watcher.go:194 log call that floods the log at shutdown.
    "quietwatcher"
  ];
in
{
  inherit patchSets;

  defaultPatches = [
    "notelemetry"
    "noautoupdate"
    "quietwatcher"
  ];

  patchAgy =
    {
      lib,
      pkgs,
      package,
      patches,
    }:
    pkgs.runCommandLocal "antigravity-cli-patched-${package.version or "custom"}"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.python3
        ];
        passthru = {
          inherit patches;
          unpatched = package;
        };
        meta = package.meta or { };
        # The manifest keeps only the input's checksum; this also guards the ELF.
        disallowedReferences = [ package ];
      }
      ''
        mkdir -p "$out/bin" "$out/share/antigravity-cli"
        python3 -I ${./_patch_agy.py} ${package}/bin/agy "$out/bin/agy" \
          --patches ${lib.escapeShellArg (lib.concatStringsSep "," patches)} >/dev/null
        # Keep the input's checksum but not its store path, which would pull the
        # unpatched package into every closure that holds this one.
        jq --arg name ${lib.escapeShellArg (lib.getName package + "-" + (package.version or "custom"))} \
          'del(.input) | .input_name = $name' "$out/bin/agy.patch.json" \
          >"$out/share/antigravity-cli/agy.patch.json"
        rm "$out/bin/agy.patch.json"
      ''
    // lib.optionalAttrs (package ? version) { inherit (package) version; };
}

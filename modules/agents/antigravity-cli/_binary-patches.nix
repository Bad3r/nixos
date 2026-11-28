# Byte patches applied to the `agy` ELF at build time by _patch_agy.py.
#
# `dynamicPatchSets` (`notelemetry`, `noautoupdate`, `quietwatcher`) are located
# dynamically at build time from Go `pclntab`, `abi.StructType` RTTI, and x86-64
# Capstone disassembly, failing closed when an expected invariant is ambiguous
# or absent. Pinned-only sets additionally require a sha256-pinned entry in
# `_agy_patcher/patches.py` (`BUILDS`).
let
  dynamicPatchSets = [
    # Options.DisableTelemetry = true for the language server (TUI, print
    # mode, --hub, acp) and for the CLI's own analytics recorder.
    "notelemetry"
    # The background updater takes its "disabled" return; without it the
    # updater ignores AGY_CLI_DISABLE_AUTO_UPDATE unless that is exactly "true".
    "noautoupdate"
    # Drops the file_watcher.go:194 log call that floods the log at shutdown.
    "quietwatcher"
  ];

  patchSets = [
    # Options.EnvironmentConfig.DevMode = true in the in-process language
    # server: TEMPLATE_DATA_DIR overrides, SetMendelFlagOverrides, and
    # /debug/pprof plus /metrics on its loopback ports without a CSRF token.
    "devmode"
    "notelemetry"
    "noautoupdate"
    "quietwatcher"
    # Disables the embedded sir_flash_lite and severe_internal_risks_agy
    # tool-call monitors and drops severe_internal_risks_agy from BLOCK to ASK.
    "agygating"
    # Switches the four pure-static PromptSection.Content methods
    # (browser_safety, chrome_default_profile, work_efficiently,
    # non_interactive_mode) from StaticString to TemplateSource{} so
    # system_prompts/<name>.tmpl loads from TEMPLATE_DATA_DIR, falling back
    # to the built-in static string when no disk template is present.
    "staticprompts"
    # Test patch: skips CheckScriptGuard at 0x9e5bc0a (xor eax, eax ; nop3).
    "testjmp"
  ];

  mkPythonEnv = pkgs: pkgs.python3.withPackages (ps: [ ps.capstone ]);

  mkPatcherSrc =
    lib:
    lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./_patch_agy.py
        ./_agy_patcher
      ];
    };
in
{
  inherit
    dynamicPatchSets
    mkPatcherSrc
    mkPythonEnv
    patchSets
    ;

  patchAgy =
    {
      lib,
      pkgs,
      package,
      patches,
    }:
    let
      pythonEnv = mkPythonEnv pkgs;
      patcherSrc = mkPatcherSrc lib;
    in
    pkgs.runCommandLocal "antigravity-cli-patched-${package.version or "custom"}"
      {
        nativeBuildInputs = [
          pkgs.jq
          pythonEnv
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
        ${pythonEnv}/bin/python3 -I ${patcherSrc}/_patch_agy.py ${package}/bin/agy "$out/bin/agy" \
          --version ${lib.escapeShellArg (package.version or "unknown")} \
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

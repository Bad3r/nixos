# Agent tool hooks shared by harnesses. Each file in hooks/ adds a
# spec to _internal.hooks.raw; a harness installs every hook that carries its
# block (e.g. claude/codex). New hooks need no per-client wiring.
#
# tests.deny/tests.allow are PreToolUse payloads; each hook with tests gets
# checks."agents/hooks/<name>", which compares them against the
# permissionDecision the hook prints (no output counts as allow).
{ config, lib, ... }:
let
  validClients = [
    "claude"
    "codex"
  ];

  rawHooks = config.flake.lib.agents._internal.hooks.raw;

  validateAllowedFields =
    context: allowedFields: attrs:
    let
      extraFields = lib.filter (field: !(lib.elem field allowedFields)) (lib.attrNames attrs);
    in
    if extraFields == [ ] then
      attrs
    else
      throw "Agent hook ${context} has unknown fields: ${lib.concatStringsSep ", " extraFields}";

  validateHookSpec =
    registryKey: spec:
    let
      validatedSpec = validateAllowedFields "'${registryKey}'" (
        [
          "name"
          "event"
          "timeout"
          "package"
          "tests"
        ]
        ++ validClients
      ) spec;
      presentClients = lib.filter (client: validatedSpec ? ${client}) validClients;
    in
    if (validatedSpec.name or null) != registryKey then
      throw "Agent hook registry key '${registryKey}' must match hook name '${validatedSpec.name or ""}'"
    else if !(builtins.isString (validatedSpec.event or null) && validatedSpec.event != "") then
      throw "Agent hook '${registryKey}' requires non-empty string field 'event'"
    else if !(builtins.isFunction (validatedSpec.package or null)) then
      throw "Agent hook '${registryKey}' requires 'package' as a function of pkgs"
    else if presentClients == [ ] then
      throw "Agent hook '${registryKey}' must declare at least one client block: ${lib.concatStringsSep ", " validClients}"
    else
      validatedSpec
      // lib.genAttrs presentClients (
        client: validateAllowedFields "'${registryKey}'.${client}" [ "matcher" ] validatedSpec.${client}
      )
      // lib.optionalAttrs (validatedSpec ? tests) {
        tests = validateAllowedFields "'${registryKey}'.tests" [
          "deny"
          "allow"
        ] validatedSpec.tests;
      };

  compiledHooks = lib.mapAttrs validateHookSpec rawHooks;

  # settings.json / hooks.json shape: { <event> = [ { matcher; hooks = [ ... ]; } ]; }
  clientHooks =
    client: pkgs:
    let
      hooks = lib.filter (hook: hook ? ${client}) (lib.attrValues compiledHooks);
      entry =
        hook:
        lib.optionalAttrs (hook.${client} ? matcher) { inherit (hook.${client}) matcher; }
        // {
          hooks = [
            (
              {
                type = "command";
                command = lib.getExe (hook.package pkgs);
              }
              // lib.optionalAttrs (hook ? timeout) { inherit (hook) timeout; }
            )
          ];
        };
    in
    lib.mapAttrs (_event: map entry) (lib.groupBy (hook: hook.event) hooks);
in
{
  options.flake.lib.agents = {
    _internal.hooks.raw = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Canonical raw hook specifications compiled into harness hook settings.";
    };

    hooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Compiled agent hooks (list) and per-harness hook settings (clients.<client> pkgs).";
    };
  };

  config = {
    flake.lib.agents.hooks = {
      list = compiledHooks;
      clients = lib.genAttrs validClients clientHooks;
    };

    perSystem =
      { pkgs, ... }:
      {
        checks = lib.mapAttrs' (
          name: hook:
          let
            cases = pkgs.writeText "agent-hook-${name}-cases.json" (builtins.toJSON hook.tests);
          in
          lib.nameValuePair "agents/hooks/${name}" (
            pkgs.runCommandLocal "agent-hook-${name}-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              set -euo pipefail
              fail=0
              for expect in deny allow; do
                while IFS= read -r case; do
                  got="$(${lib.getExe (hook.package pkgs)} <<<"$case" | jq -rs '.[0].hookSpecificOutput.permissionDecision // "allow"')"
                  if [ "$got" != "$expect" ]; then
                    echo "expected $expect, got $got: $case" >&2
                    fail=1
                  fi
                done < <(jq -c ".$expect // [] | .[]" ${cases})
              done
              [ "$fail" -eq 0 ]
              touch "$out"
            ''
          )
        ) (lib.filterAttrs (_name: hook: hook ? tests) compiledHooks);
      };
  };
}

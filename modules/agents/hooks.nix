# Agent tool hooks shared by harnesses. Each file in hooks/ adds a
# spec to _internal.hooks.raw; a harness installs every hook that carries its
# block (e.g. claude/codex). New hooks need no per-client wiring.
#
# tests.deny/tests.ask/tests.allow are PreToolUse payloads; each hook with
# tests gets checks."agents/hooks/<name>", which compares them against the
# permissionDecision the hook prints (no output counts as allow).
{ config, lib, ... }:
let
  registry = import ./_registry.nix { inherit lib; };
  inherit (registry) validClients;
  validateAllowedFields = registry.validateAllowedFields "hook";

  rawHooks = config.flake.lib.agents._internal.hooks.raw;

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
    else if
      validatedSpec ? timeout && !(builtins.isInt validatedSpec.timeout && validatedSpec.timeout > 0)
    then
      throw "Agent hook '${registryKey}' field 'timeout' must be a positive integer (seconds)"
    else if presentClients == [ ] then
      throw "Agent hook '${registryKey}' must declare at least one client block: ${lib.concatStringsSep ", " validClients}"
    else
      validatedSpec
      // lib.genAttrs presentClients (
        client: validateClientBlock registryKey client validatedSpec.${client}
      )
      // lib.optionalAttrs (validatedSpec ? tests) {
        tests = validateTests registryKey validatedSpec.tests;
      };

  validateClientBlock =
    registryKey: client: block:
    let
      context = "'${registryKey}'.${client}";
    in
    if !builtins.isAttrs block then
      throw "Agent hook ${context} must be an attribute set"
    else if block ? matcher && !(builtins.isString block.matcher && block.matcher != "") then
      throw "Agent hook ${context}.matcher must be a non-empty string"
    else
      validateAllowedFields context [ "matcher" ] block;

  validateTests =
    registryKey: tests:
    let
      context = "'${registryKey}'.tests";
      validated = validateAllowedFields context [
        "deny"
        "ask"
        "allow"
      ] tests;
      badKinds = lib.filter (
        kind: !(builtins.isList validated.${kind} && lib.all builtins.isAttrs validated.${kind})
      ) (lib.attrNames validated);
    in
    if badKinds != [ ] then
      throw "Agent hook ${context}.${lib.concatStringsSep ", " badKinds} must be a list of payload attribute sets"
    else
      validated;

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
              for expect in deny ask allow; do
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

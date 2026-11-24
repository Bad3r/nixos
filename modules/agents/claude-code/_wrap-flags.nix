# Wrapper flags baked into the Nix-installed claude binary (nixos.nix) and
# exercised by claude-code/launcher-env in checks.nix.
{ lib }:
let
  claudeEnv = import ./_env.nix;

  setFlags = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      name: value:
      let
        flag = if lib.elem name claudeEnv.callerOverridable then "--set-default" else "--set";
      in
      "${flag} ${name} ${lib.escapeShellArg value}"
    ) (builtins.removeAttrs claudeEnv.vars claudeEnv.launchOnly)
  );

  # Guarded, not --set: claude-rc lifts these for one launch, and a plain
  # --set here would be applied in-process where no outer wrapper reaches.
  launchOnlyRun = lib.optionalString (claudeEnv.launchOnly != [ ]) (
    "--run "
    + lib.escapeShellArg (
      "if [ -z \""
      + "$"
      + "{${claudeEnv.launchOnlyEscape}:-}\" ]; then export "
      + lib.concatStringsSep " " (
        map (name: "${name}=${lib.escapeShellArg claudeEnv.vars.${name}}") claudeEnv.launchOnly
      )
      + "; else unset ${lib.concatStringsSep " " claudeEnv.launchOnly} ${claudeEnv.launchOnlyEscape}; fi"
    )
  );

  strippedNames = lib.attrNames claudeEnv.vars ++ [ "DISABLE_NON_ESSENTIAL_MODEL_CALLS" ];
in
{
  inherit
    setFlags
    launchOnlyRun
    strippedNames
    ;
}

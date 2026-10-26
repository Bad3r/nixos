# Evaluate all checks once, then build runtime checks from their store paths.
# modules/configurations/nixos.nix registers every host toplevel in checks.
checks:
let
  names = builtins.attrNames checks;
  hosts = builtins.filter (name: builtins.match "configurations/nixos/.+" name != null) names;
  runtimeNames = builtins.filter (
    name: (checks.${name}.runtimeCheck or false) || builtins.match "script-tests-.*" name != null
  ) names;
  runtimeTarget =
    name:
    let
      check = checks.${name};
      # Match flake installables' output selection when using a store path.
      outputs =
        if check.outputSpecified or false then
          [ check.outputName ]
        else
          check.meta.outputsToInstall or [ "out" ];
    in
    if outputs == [ ] then
      throw "runtime check ${name} selects no outputs"
    else
      "${check.drvPath}^${builtins.concatStringsSep "," outputs}";
in
if hosts == [ ] then
  throw "no nixosConfigurations checks found"
else if runtimeNames == [ ] then
  throw "no runtime checks found"
else
  {
    checks = builtins.mapAttrs (_: check: check.drvPath) checks;
    inherit hosts;
    runtimeChecks = map runtimeTarget runtimeNames;
  }

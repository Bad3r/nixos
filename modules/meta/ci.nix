{
  config,
  withSystem,
  ...
}:
let
  helpers = config.flake.lib.nixos or { };
  defaultSystem = builtins.head config.systems;
  mkEvalCheck =
    name: expr:
    withSystem defaultSystem (psArgs: builtins.seq expr (psArgs.pkgs.runCommand name { } "touch $out"));
in
{
  flake.checks = {
    helpers-exist = mkEvalCheck "helpers-exist-ok" (
      if (helpers ? getApp) && (helpers ? getApps) && (helpers ? getAppOr) && (helpers ? hasApp) then
        "ok"
      else
        throw "missing helper(s) under config.flake.lib.nixos"
    );
  };

  perSystem = _: { };
}

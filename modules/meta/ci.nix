{
  config,
  withSystem,
  ...
}:
let
  helpers = config.flake.lib.nixos or { };
  assertList = v: if builtins.isList v then true else throw "role module imports not a list";
  hasRoles = builtins.hasAttr "roles" config.flake.nixosModules;
  roleModuleExists =
    name: if hasRoles then builtins.hasAttr name config.flake.nixosModules.roles else false;
  defaultSystem = builtins.head config.systems;
  mkEvalCheck =
    name: expr:
    withSystem defaultSystem (psArgs: builtins.seq expr (psArgs.pkgs.runCommand name { } "touch $out"));
in
{
  flake.checks = {
    role-modules-exist = mkEvalCheck "role-modules-exist-ok" (
      if roleModuleExists "dev" && roleModuleExists "media" && roleModuleExists "net" then
        "ok"
      else
        throw "role module missing"
    );

    role-modules-structure = mkEvalCheck "role-modules-structure-ok" (
      builtins.seq (assertList config.flake.nixosModules.roles.dev.imports) (
        builtins.seq (assertList config.flake.nixosModules.roles.media.imports) (
          builtins.seq (assertList config.flake.nixosModules.roles.net.imports) "ok"
        )
      )
    );

    helpers-exist = mkEvalCheck "helpers-exist-ok" (
      if (helpers ? getApp) && (helpers ? getApps) && (helpers ? getAppOr) && (helpers ? hasApp) then
        "ok"
      else
        throw "missing helper(s) under config.flake.lib.nixos"
    );
  };

  perSystem = _: { };
}

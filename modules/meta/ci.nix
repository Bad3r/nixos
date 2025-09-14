{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        role-aliases-exist = pkgs.writeText "role-aliases-exist-ok" (
          if
            (config.flake.nixosModules ? "role-dev")
            && (config.flake.nixosModules ? "role-media")
            && (config.flake.nixosModules ? "role-net")
          then
            "ok"
          else
            throw "role-* alias missing"
        );

        role-aliases-structure = pkgs.writeText "role-aliases-structure-ok" (
          let
            assertList = v: if builtins.isList v then true else throw "role alias imports not a list";
          in
          builtins.seq (
            assertList config.flake.nixosModules."role-dev".imports
            && assertList config.flake.nixosModules."role-media".imports
            && assertList config.flake.nixosModules."role-net".imports
          ) "ok"
        );

        helpers-exist = pkgs.writeText "helpers-exist-ok" (
          if
            (config.flake.lib.nixos ? getApp)
            && (config.flake.lib.nixos ? getApps)
            && (config.flake.lib.nixos ? getAppOr)
            && (config.flake.lib.nixos ? hasApp)
          then
            "ok"
          else
            throw "missing one or more helper functions"
        );
      };

      # No managed files emitted here; workflow check is handled elsewhere.
    };
}

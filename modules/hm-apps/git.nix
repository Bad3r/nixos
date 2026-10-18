/*
  Package: git
  Description: Distributed version control system.
  Homepage: https://git-scm.com/
*/

_: {
  flake.homeManagerModules.apps.git =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "git" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.git = {
          enable = true;
          # maintenance needs it: systemd resolves a bare `git` ExecStart without PATH.
          package = lib.attrByPath [ "programs" "git" "extended" "package" ] pkgs.git osConfig;
        };
      };
    };
}

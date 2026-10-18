/*
  Package: nushell
  Description: Modern shell written in Rust.
  Homepage: https://www.nushell.sh/
  Documentation: https://www.nushell.sh/book/
  Repository: https://github.com/nushell/nushell
*/
_: {
  flake.homeManagerModules.apps.nushell =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "nushell" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.nushell = {
          enable = true;
          # NOTE: Cannot use `package = null` here because HM nushell plugins
          # require the package reference to be installed alongside them.
          package = osConfig.programs.nushell.extended.package;
        };
      };
    };
}

/*
  Internal: shared Gecko-browser keyboard shortcut files
  Description: Home Manager files for per-profile browser shortcut overrides.
*/

{ lib }:
let
  customKeysJson =
    builtins.toJSON {
      key_inspector = { };
    }
    + "\n";
in
{
  mkCustomKeysFiles =
    browserCfg:
    lib.mapAttrs' (
      _: profile:
      lib.nameValuePair "${browserCfg.profilesPath}/${profile.path}/customKeys.json" {
        text = customKeysJson;
        force = true;
      }
    ) browserCfg.profiles;
}

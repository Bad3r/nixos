/*
  Package: antigravity-cli
  Description: Home Manager glue for Google Antigravity settings.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/cli
  Repository: nil

  Summary:
    * Enables the upstream `programs.antigravity` Home Manager module when the NixOS antigravity-cli counterpart is enabled.
    * Lets the NixOS module own the llm-agents.nix package install while HM manages Antigravity user settings.

  Notes:
    * Upstream HM `programs.antigravity.package` is nullable, so `package = null` avoids duplicate installation.
*/
_: {
  flake.homeManagerModules.apps."antigravity-cli" =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "antigravity-cli" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.antigravity = {
          enable = true;
          package = null;
        };
      };
    };
}

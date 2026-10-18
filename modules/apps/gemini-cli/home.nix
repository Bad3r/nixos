/*
  Package: gemini-cli
  Description: Home Manager glue for Gemini CLI settings and user assets.
  Homepage: https://github.com/google-gemini/gemini-cli
  Documentation: https://www.geminicli.com/docs/
  Repository: https://github.com/google-gemini/gemini-cli

  Summary:
    * Enables the upstream `programs.gemini-cli` Home Manager module when the NixOS counterpart is enabled.
    * Lets the NixOS module own the llm-agents.nix package install while HM manages settings, commands, policies, context, and skills.

  Notes:
    * Upstream HM `programs.gemini-cli.package` is nullable, so `package = null` avoids duplicate installation.
*/
_: {
  flake.homeManagerModules.apps."gemini-cli" =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "gemini-cli" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.gemini-cli = {
          enable = true;
          package = null;
        };
      };
    };
}

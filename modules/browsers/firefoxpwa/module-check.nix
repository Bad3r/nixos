/*
  Check: the firefoxpwa Home Manager module evaluates (modules/browsers/firefoxpwa).

  dmail-check.nix builds packages/firefoxpwa-dmail-install against a stub
  firefoxpwa, never the module: home.nix and dmail.nix's config = lib.mkIf
  (dmailEnabled && firefoxpwaEnabled && geckoFileExists) { ... } blocks are only
  forced when the condition is true, and CI never has gecko.yaml (the secrets
  submodule is absent there by design; see .github/workflows/check.yml), so
  every attribute those blocks declare, ExecStart, Environment, the sops
  secret, has never actually been evaluated by CI. A typo or a reference to a
  removed binding inside them would reach main and fail only at the next real
  switch.

  Builds a standalone Home Manager configuration the same way
  modules/home-manager/checks.nix does, with osConfig stubbed to enable both
  toggles and secretsRoot pointed at module-check-fixtures (an in-repo,
  non-secret gecko.yaml), so both mkIf conditions evaluate to true here
  regardless of what the real secrets submodule holds. builtins.deepSeq
  forces the specific attributes that matter before returning the
  configuration's home-files, home-manager's own eval-smoke-test derivation
  (never built by `nix flake check`, only evaluated).
*/
{
  lib,
  inputs,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."browsers/firefoxpwa-module-eval" =
        let
          mkHm =
            {
              firefoxpwaConfig,
              secretsRoot ? ./module-check-fixtures,
            }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                inputs.sops-nix.homeManagerModules.sops
                config.flake.homeManagerModules.browsers.firefoxpwa
                {
                  home = {
                    username = "hm-smoke";
                    homeDirectory = "/tmp/hm-smoke";
                    stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                    enableNixpkgsReleaseCheck = false;
                  };
                  programs.home-manager.enable = true;
                  # This check forces module output, not secret decryption. Keep
                  # the fixture non-secret and validate only the generated
                  # manifest shape.
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                }
              ];
              extraSpecialArgs = {
                osConfig.programs.firefoxpwa = firefoxpwaConfig;
                inherit secretsRoot;
              };
            };
          hm = mkHm {
            firefoxpwaConfig = {
              extended.enable = true;
              dmail.enable = true;
            };
          };
          noFirefoxpwa = mkHm {
            firefoxpwaConfig = {
              extended.enable = false;
              dmail.enable = true;
            };
          };
          noGecko = mkHm {
            firefoxpwaConfig = {
              extended.enable = true;
              dmail.enable = true;
            };
            secretsRoot = "${./module-check-fixtures}/missing";
          };
        in
        assert lib.assertMsg
          (lib.any (lib.hasInfix "extended.enable is false") noFirefoxpwa.config.warnings)
          "browsers/firefoxpwa-module-eval: dmail.enable without extended.enable must warn";
        assert lib.assertMsg (lib.any (lib.hasInfix "gecko.yaml is missing") noGecko.config.warnings)
          "browsers/firefoxpwa-module-eval: a missing gecko.yaml must warn";
        assert lib.assertMsg
          (!builtins.hasAttr "firefoxpwa-dmail" noFirefoxpwa.config.systemd.user.services)
          "browsers/firefoxpwa-module-eval: dmail.enable without extended.enable must not declare the install unit";
        assert lib.assertMsg (
          !builtins.hasAttr "firefoxpwa-dmail" noGecko.config.systemd.user.services
        ) "browsers/firefoxpwa-module-eval: a missing gecko.yaml must not declare the install unit";
        assert lib.assertMsg (
          !builtins.hasAttr "firefoxpwa/dmail/url" noGecko.config.sops.secrets
        ) "browsers/firefoxpwa-module-eval: a missing gecko.yaml must not declare the sops secret";
        assert lib.assertMsg (
          hm.config.warnings == [ ]
        ) "browsers/firefoxpwa-module-eval: the enabled configuration must not warn";
        builtins.deepSeq {
          execStart = hm.config.systemd.user.services.firefoxpwa-dmail.Service.ExecStart;
          environment = hm.config.systemd.user.services.firefoxpwa-dmail.Service.Environment;
          secretPath = hm.config.sops.secrets."firefoxpwa/dmail/url".path;
          sessionVariables = {
            inherit (hm.config.home.sessionVariables) FFPWA_USERDATA XDG_DATA_HOME;
          };
          activation = hm.config.home.activation.ensureFirefoxpwaSecretDir;
          warnings = {
            enabled = hm.config.warnings;
            noFirefoxpwa = noFirefoxpwa.config.warnings;
            noGecko = noGecko.config.warnings;
          };
        } hm.config.home-files;
    };
}

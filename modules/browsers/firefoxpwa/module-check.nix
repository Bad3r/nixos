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

  m365.nix has the same gap for a different reason: no host enables
  programs.firefoxpwa.m365 yet, so its mkIf blocks are unforced everywhere.

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
          # osConfig is a plain attrset here, not an evaluated NixOS
          # configuration, so the option default in ./apps.nix does not apply
          # and the catalog has to be named. Imported rather than restated, so
          # this evaluates the list hosts actually get.
          m365 = {
            enable = true;
            apps = import ./_m365-apps.nix;
          };
          hm = mkHm {
            firefoxpwaConfig = {
              extended.enable = true;
              dmail.enable = true;
              inherit m365;
            };
          };
          noFirefoxpwa = mkHm {
            firefoxpwaConfig = {
              extended.enable = false;
              dmail.enable = true;
              inherit m365;
            };
          };
          noM365Apps = mkHm {
            firefoxpwaConfig = {
              extended.enable = true;
              dmail.enable = false;
              m365 = {
                enable = true;
                apps = [ ];
              };
            };
          };
          noGecko = mkHm {
            firefoxpwaConfig = {
              extended.enable = true;
              dmail.enable = true;
              m365.enable = false;
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
        assert lib.assertMsg (lib.any (lib.hasInfix "m365.apps is empty") noM365Apps.config.warnings)
          "browsers/firefoxpwa-module-eval: m365.enable with an empty app list must warn";
        assert lib.assertMsg (!builtins.hasAttr "firefoxpwa-m365" noFirefoxpwa.config.systemd.user.services)
          "browsers/firefoxpwa-module-eval: m365.enable without extended.enable must not declare the install unit";
        assert lib.assertMsg (
          !builtins.hasAttr "firefoxpwa-m365" noM365Apps.config.systemd.user.services
        ) "browsers/firefoxpwa-module-eval: an empty app list must not declare the install unit";
        assert lib.assertMsg (
          !builtins.hasAttr "firefoxpwa-m365" noGecko.config.systemd.user.services
        ) "browsers/firefoxpwa-module-eval: m365.enable = false must not declare the install unit";
        assert lib.assertMsg (
          hm.config.warnings == [ ]
        ) "browsers/firefoxpwa-module-eval: the enabled configuration must not warn";
        # Forcing the unit below proves the attribute evaluates, not that it
        # names the right unit, and systemd ignores an After= on a unit that
        # does not exist rather than reporting it: a typo here would be silent
        # at switch and at login. The installers' shared lock is what actually
        # keeps the two apart, so this only has to hold the ordering that keeps
        # the common case off the lock.
        assert lib.assertMsg
          (lib.elem "firefoxpwa-dmail.service" hm.config.systemd.user.services.firefoxpwa-m365.Unit.After)
          "browsers/firefoxpwa-module-eval: the m365 unit must be ordered after the dmail unit";
        assert lib.assertMsg
          (
            hm.config.systemd.user.services.firefoxpwa-m365.Service.SuccessExitStatus == "78"
            && hm.config.systemd.user.services.firefoxpwa-m365.Service.RestartPreventExitStatus == "78"
          )
          "browsers/firefoxpwa-module-eval: a permanent m365 refusal must exit EX_CONFIG 78, which no installer fault produces";
        # Keep the retry window long enough for every bounded attempt to count
        # toward StartLimitBurst. Otherwise a timeout can land alone in the
        # sliding window and the unit retries for the rest of the session.
        assert
          let
            m365Unit = hm.config.systemd.user.services.firefoxpwa-m365;
          in
          lib.assertMsg
            (
              m365Unit.Unit.StartLimitIntervalSec >= m365Unit.Unit.StartLimitBurst
              * (m365Unit.Service.TimeoutStartSec + m365Unit.Service.RestartMaxDelaySec)
            )
            "browsers/firefoxpwa-module-eval: StartLimitIntervalSec must cover StartLimitBurst * (TimeoutStartSec + RestartMaxDelaySec)";
        builtins.deepSeq {
          # The whole unit, not selected attributes: a removed binding in its
          # Unit or Install blocks must fail this check too.
          dmail = hm.config.systemd.user.services.firefoxpwa-dmail;
          secretPath = hm.config.sops.secrets."firefoxpwa/dmail/url".path;
          # The whole unit also carries the restart policy that gives a failed
          # run its rerun, and no host enables the toggle, so nothing else would
          # force it.
          m365 = hm.config.systemd.user.services.firefoxpwa-m365;
          sessionVariables = {
            inherit (hm.config.home.sessionVariables) FFPWA_USERDATA XDG_DATA_HOME;
          };
          activation = hm.config.home.activation.ensureFirefoxpwaSecretDir;
          warnings = {
            enabled = hm.config.warnings;
            noFirefoxpwa = noFirefoxpwa.config.warnings;
            noM365Apps = noM365Apps.config.warnings;
            noGecko = noGecko.config.warnings;
          };
        } hm.config.home-files;
    };
}

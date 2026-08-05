/*
  Check: the firefoxpwa NixOS-scope option module (./apps.nix).

  ./module-check.nix forces the Home Manager side. This forces the other half,
  which nothing else evaluates either: no host enables programs.firefoxpwa.m365,
  so its assertions and the launcher-name registry they read are unforced
  everywhere, and an assertion that never evaluates is indistinguishable from
  one that never fires.

  Evaluated through lib.evalModules with the handful of NixOS options this
  module writes to declared as stubs, rather than a full nixosSystem: the
  subject is the module's own options and assertions, and a stub that goes
  missing fails loudly by naming the option.

  ./apps.nix is imported directly, the way ./m365-check.nix imports
  ./_m365-apps.nix and the installers it drives. flake.nixosModules.browsers is
  one deferred module rather than an attrset, so the module cannot be reached
  through it by name, and flake.lib.nixosBrowsers, which does flatten it, must
  not be read from perSystem.
*/
{
  lib,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      evalWith =
        firefoxpwa:
        (lib.evalModules {
          modules = [
            (import ./apps.nix { }).flake.nixosModules.browsers.firefoxpwa
            {
              options = {
                environment.systemPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                };
                assertions = lib.mkOption {
                  type = lib.types.listOf lib.types.unspecified;
                  default = [ ];
                };
                warnings = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
              };
              config = {
                _module.args.pkgs = pkgs;
                programs.firefoxpwa = firefoxpwa;
              };
            }
          ];
        }).config;

      failures = evaled: lib.filter (a: !a.assertion) evaled.assertions;

      # The url type rejects by throwing rather than by failing an assertion, so
      # the two need different observations. Forced through the app list, since
      # a type only applies when its value is forced.
      accepts =
        url:
        (builtins.tryEval (
          builtins.deepSeq
            (evalWith {
              extended.enable = true;
              m365 = {
                enable = true;
                apps = [
                  {
                    key = "probe";
                    name = "Probe";
                    inherit url;
                  }
                ];
              };
            }).programs.firefoxpwa.m365.apps
            true
        )).success;
      failsWith = evaled: fragment: lib.any (a: lib.hasInfix fragment a.message) (failures evaled);

      # The launcher name is the idempotency key in a config.json every site
      # installer shares, so this is the collision the registry exists for: one
      # site's name claimed by another's entry.
      collides = evalWith {
        extended.enable = true;
        dmail.enable = true;
        m365 = {
          enable = true;
          apps = [
            {
              key = "work-mail";
              name = "DMail";
              url = "https://mail.example/";
            }
          ];
        };
      };

      # The same pair without the collision: the shipped catalog alongside the
      # DMail site, which is what a host enabling both actually gets.
      shipped = evalWith {
        extended.enable = true;
        dmail.enable = true;
        m365.enable = true;
      };

      # Registered only while the site is enabled, or a disabled installer would
      # reserve a name nothing installs.
      dmailOff = evalWith {
        extended.enable = true;
        m365 = {
          enable = true;
          apps = [
            {
              key = "work-mail";
              name = "DMail";
              url = "https://mail.example/";
            }
          ];
        };
      };

      duplicateKeys = evalWith {
        extended.enable = true;
        m365 = {
          enable = true;
          apps = [
            {
              key = "word";
              name = "Word";
              url = "https://word.example/";
            }
            {
              key = "word";
              name = "Excel";
              url = "https://excel.example/";
            }
          ];
        };
      };
    in
    {
      checks."browsers/firefoxpwa-apps-eval" =
        assert lib.assertMsg (failsWith collides "same launcher name")
          "browsers/firefoxpwa-apps-eval: an m365 entry claiming the DMail site's launcher name must fail an assertion";
        assert lib.assertMsg (
          failures shipped == [ ]
        ) "browsers/firefoxpwa-apps-eval: the shipped catalog alongside DMail must not fail an assertion";
        assert lib.assertMsg (
          failures dmailOff == [ ]
        ) "browsers/firefoxpwa-apps-eval: a name is only claimed while its site is enabled";
        assert lib.assertMsg (failsWith duplicateKeys "duplicate keys")
          "browsers/firefoxpwa-apps-eval: two m365 entries sharing a key must fail an assertion";
        # The m365-only duplicate-name assertion was dropped as subsumed by the
        # union above; this is the intra-list case it used to cover, and it
        # reaches the union only through siteNames = m365Names in ./apps.nix.
        assert lib.assertMsg (failsWith (evalWith {
          extended.enable = true;
          m365 = {
            enable = true;
            apps = [
              {
                key = "word";
                name = "Word";
                url = "https://word.example/";
              }
              {
                key = "word-2";
                name = "Word";
                url = "https://word-2.example/";
              }
            ];
          };
        }) "same launcher name")
          "browsers/firefoxpwa-apps-eval: two m365 entries sharing a name must fail an assertion";
        assert lib.assertMsg (lib.elem "DMail" shipped.programs.firefoxpwa.siteNames)
          "browsers/firefoxpwa-apps-eval: an enabled site must register its launcher name";
        assert lib.assertMsg (accepts "https://word.cloud.microsoft/")
          "browsers/firefoxpwa-apps-eval: a plain https start URL must be accepted";
        assert lib.assertMsg (accepts "https://word.cloud.microsoft/a/b?q=1@2")
          "browsers/firefoxpwa-apps-eval: an @ outside the authority must be accepted";
        # Refused at runtime by the installer because the scope derived from it
        # drops the userinfo and could then never contain the start URL. These
        # are static strings, so the refusal belongs at eval.
        assert lib.assertMsg (
          !accepts "https://user:pass@word.cloud.microsoft/"
        ) "browsers/firefoxpwa-apps-eval: a start URL embedding credentials must be rejected";
        assert lib.assertMsg (
          !accepts "word.cloud.microsoft"
        ) "browsers/firefoxpwa-apps-eval: a scheme-less start URL must be rejected";
        pkgs.runCommand "firefoxpwa-apps-eval" { } ''
          echo "the firefoxpwa option module's assertions evaluate and fire" >"$out"
        '';
    };
}

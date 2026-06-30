/*
  Custom overlay: firefoxpwa runtime extension policy

  PWAsForFirefox ships its own patched Firefox runtime under
  `$out/share/firefoxpwa/runtime` and runs each web app in an isolated profile.
  Those profiles are not Home Manager `programs.firefox` profiles, so the only
  declarative hook for installing extensions into them is a Firefox enterprise
  policy file in the runtime's `distribution/` directory (the same mechanism
  `wrapFirefox` uses for normal Firefox).

  This overlay injects that policy file into the unwrapped package. The policy
  force-installs uBlock Origin and 1Password into every PWA profile, and adds
  Tridactyl and the Tab Reloader keep-alive extension as user-removable installs.
  nixpkgs builds `firefoxpwa = wrapFirefox firefoxpwa-unwrapped { }`, so
  overriding only the unwrapped package lets the package-set fixpoint rebuild the
  wrapped `firefoxpwa` around the patched runtime, with no manual re-wrap. The
  policy set is owned by modules/hm-apps/_gecko-extensions.nix so add-on IDs stay
  single-sourced.

  Gated on `programs.firefoxpwa.extended.enable`; see modules/apps/firefoxpwa.nix.
*/
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.firefoxpwa.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (
            final: prev:
            let
              geckoExtensions = import ../hm-apps/_gecko-extensions.nix {
                inherit lib;
                pkgs = final;
                config = { };
              };
              runtimePolicies = final.writeText "firefoxpwa-runtime-policies.json" (
                builtins.toJSON { policies = geckoExtensions.firefoxpwaRuntimePolicies; }
              );
            in
            {
              # The runtime lives in the unwrapped output (the wrapped binary
              # reaches it through FFPWA_SYSDATA), so the policy file must be
              # added there. This postInstall runs after the package's own, which
              # has copied the runtime and run `firefoxpwa runtime patch`; the
              # runtime tree is already writable (chmod -R +w in the base build).
              # Overriding only the unwrapped package is enough: the wrapped
              # `firefoxpwa` is `wrapFirefox firefoxpwa-unwrapped { }` in the
              # package set, so the fixpoint re-wraps it around this override.
              firefoxpwa-unwrapped = prev.firefoxpwa-unwrapped.overrideAttrs (old: {
                postInstall =
                  (old.postInstall or "")
                  + "\n"
                  + ''
                    install -Dm644 ${runtimePolicies} \
                      "$out/share/firefoxpwa/runtime/distribution/policies.json"
                  '';
              });
            }
          )
        ];
      };
    };
in
{
  flake.customOverlays.firefoxpwa = Overlay;
}

_: {
  # Unfree extensions bundled by the shared gecko extension list in
  # `_gecko-extensions.nix`. Names match `lib.getName` on each addon
  # derivation.
  nixpkgs.allowedUnfreePackages = [
    "languagetool"
    "onepassword-password-manager"
    "wappalyzer"
  ];

  flake.homeManagerModules.apps.firefox =
    {
      osConfig,
      lib,
      pkgs,
      config,
      inputs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
      gecko = import ./_gecko-mk-profile.nix {
        inherit
          pkgs
          inputs
          lib
          config
          ;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.firefox = {
          enable = true;
          # nixpkgs wraps Firefox with MOZ_LEGACY_PROFILES=1, which forces
          # reads from ~/.mozilla/firefox. Home Manager stateVersion 26.05
          # switched this default to $XDG_CONFIG_HOME/mozilla/firefox, which
          # Firefox ignores. Pin to the legacy path so HM writes where
          # Firefox reads.
          configPath = ".mozilla/firefox";
          # Bake the Tridactyl native messaging host into the Firefox
          # wrapper so its manifest lands under
          # `$out/lib/mozilla/native-messaging-hosts/` (one of the
          # directories Firefox actually searches). Installing
          # `pkgs.tridactyl-native` via `home.packages` would put the
          # manifest in `~/.nix-profile/...`, which Firefox does not
          # discover.
          package = osConfig.programs.firefox.extended.package.override {
            nativeMessagingHosts = [ pkgs.tridactyl-native ];
          };

          inherit (gecko) policies;

          languagePacks = [ "en-US" ];

          profiles = {
            primary = gecko.mkProfile {
              id = 0;
              packages = gecko.primaryPackages;
            };

            work = gecko.mkProfile {
              id = 1;
              packages = gecko.workPackages;
            };

            ephemeral = gecko.mkProfile {
              id = 2;
              packages = gecko.ephemeralPackages;
            };
          };
        };
      };
    };
}

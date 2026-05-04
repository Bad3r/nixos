/*
  Package: doom-emacs
  Description: Doom Emacs framework built reproducibly with Nix via marienz/nix-doom-emacs-unstraightened.
  Homepage: https://github.com/doomemacs/doomemacs
  Documentation: https://docs.doomemacs.org/
  Repository: https://github.com/marienz/nix-doom-emacs-unstraightened

  Summary:
    * Builds Doom Emacs with a sealed package set (no straight.el) by snapshotting modules and dependencies through Nix.
    * Bundles a user doomdir (init.el / packages.el / config.el) into the produced Emacs derivation so activation is fully declarative.

  Options:
    enable: Toggle the doom-emacs integration; the actual package is installed by the Home Manager module.
    package: Emacs derivation passed to Unstraightened (defaults to pkgs.emacs from the emacs-overlay).
    doomDir: Path to the doomdir bundled into the build (defaults to the upstream Doom starter templates).
    enableService: Enable the Home Manager `services.emacs` user daemon backed by Doom.

  Notes:
    * Package sourced from nix-doom-emacs-unstraightened (github:marienz/nix-doom-emacs-unstraightened).
    * Adds inputs.emacs-overlay.overlays.default to nixpkgs.overlays for the host whenever `enable = true`.
      That registration is global: it changes pkgs.emacs and every package that builds against the Emacs
      tree (notmuch, mu, mu4e, pdf-tools, anything using emacsPackages / emacsWithPackages). Account for
      that side-effect when debugging unrelated Emacs regressions.
    * Wires `nix-community.cachix.org` (emacs-overlay artefacts) and
      `doom-emacs-unstraightened.cachix.org` (Doom build artefacts) into
      `nix.settings.extra-substituters` so substitution covers both layers. Trust
      keys are mirrored in `extra-trusted-public-keys`.
    * Installs the unfree `symbola` font system-wide; Doom uses it as the Unicode
      fallback face and `doom doctor` warns when it is missing.
    * Configuration and install delegated to Home Manager (modules/hm-apps/doom-emacs.nix).
    * Override doomDir to point at a real Doom configuration for a personalised setup.
*/
{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "symbola" ];

  flake.nixosModules.apps.doom-emacs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.doom-emacs.extended;
      cacheSubstituter = "https://nix-community.cachix.org";
      cachePublicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
      doomCacheSubstituter = "https://doom-emacs-unstraightened.cachix.org";
      doomCachePublicKey = "doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4=";
    in
    {
      options.programs.doom-emacs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this host uses Doom Emacs built via nix-doom-emacs-unstraightened.
            Activation happens through the matching Home Manager module
            (modules/hm-apps/doom-emacs.nix), which imports the upstream homeModule.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.emacs;
          defaultText = lib.literalExpression "pkgs.emacs";
          description = ''
            Emacs derivation passed to Unstraightened. The default tracks
            `pkgs.emacs` from the emacs-overlay registered by this module.
            Set this to e.g. `pkgs.emacs-pgtk` to switch variants.
          '';
        };

        doomDir = lib.mkOption {
          type = lib.types.path;
          default = ./doom-emacs-doomdir;
          defaultText = lib.literalExpression "./doom-emacs-doomdir";
          description = ''
            Path to the Doom configuration directory (init.el / packages.el / config.el)
            bundled into the build. The default ships the upstream Doom starter
            templates (static/{init,packages,config}.example.el) and gives a working
            evil/vertico/corfu/magit setup out of the box. Override to layer in a
            personal doomdir.
          '';
        };

        enableService = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to enable the Home Manager `services.emacs` user daemon. The
            upstream homeModule wires `services.emacs.package` to the Doom build
            automatically, so the daemon launches the Unstraightened binary.
            Opt in per host once Doom starts cleanly to avoid an `systemctl --user`
            restart loop on configuration errors.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [ inputs.emacs-overlay.overlays.default ];
        nix.settings.extra-substituters = lib.mkAfter [
          cacheSubstituter
          doomCacheSubstituter
        ];
        nix.settings.extra-trusted-public-keys = lib.mkAfter [
          cachePublicKey
          doomCachePublicKey
        ];
        fonts.packages = [ pkgs.symbola ];
      };
    };
}

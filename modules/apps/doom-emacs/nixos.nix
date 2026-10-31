/*
  Package: doom-emacs
  Description: Doom Emacs framework built reproducibly with Nix via marienz/nix-doom-emacs-unstraightened.
  Homepage: https://github.com/doomemacs/doomemacs
  Documentation: https://docs.doomemacs.org/
  Repository: https://github.com/doomemacs/core

  Notes:
    * Enabling it applies emacs-overlay host-wide, which replaces `pkgs.emacs` and every package built against it.
*/
{ inputs, lib, ... }:
let
  renderedDoom = import ./_doomdir.nix { inherit lib; };

  mkRenderedDoomDir =
    pkgs:
    pkgs.runCommandLocal "doom-emacs-rendered-doomdir" { } (
      ''
        mkdir -p "$out"
      ''
      + lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: text: ''
          install -Dm0444 ${pkgs.writeText "doom-emacs-${name}" text} "$out/${name}"
        '') renderedDoom.generatedFiles
      )
    );
in
{
  nixpkgs.allowedUnfreePackages = [ "symbola" ];

  perSystem =
    { pkgs, ... }:
    {
      checks.doom-emacs-rendered-doomdir = mkRenderedDoomDir pkgs;
    };

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
            (modules/apps/doom-emacs/home.nix), which imports the upstream homeModule.
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
          default = ./doomdir;
          defaultText = lib.literalExpression "./doomdir";
          description = ''
            Path to the Doom configuration directory (init.el / packages.el / config.el)
            bundled into the build. The default stays on the committed static
            starter doomdir because nix-doom-emacs-unstraightened imports
            generated intermediates during evaluation; changing the default
            contents requires that intermediate output to be realized before
            no-build flake validation can pass. Override to layer in a personal
            doomdir.
          '';
        };

        enableLanguageTooling = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to add tree-sitter grammars plus language servers and
            formatters to Doom's runtime path. Enable this when `doomDir`
            activates the matching Doom modules. The bundled starter doomdir
            enables Nix tree-sitter syntax only, so the default avoids pulling
            in the broader language-tool closure.
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

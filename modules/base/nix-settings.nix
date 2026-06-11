{ lib, ... }:
let
  settings = {
    # Auto-trust flake nixConfig settings (safe for own repositories)
    accept-flake-config = true;
    # Disabled due to upstream nixpkgs warning in make-options-doc
    # See: https://github.com/NixOS/nixpkgs/issues/485682
    abort-on-warn = false;
    # IFD consumers in this repo (mirrors flake.nix#nixConfig):
    #   * nix-doom-emacs-unstraightened: evaluates a JSON manifest produced
    #     by a build derivation.
    # Update both this comment and flake.nix when adding or removing IFD
    # consumers.
    allow-import-from-derivation = true;
    auto-optimise-store = lib.mkDefault true;
    cores = lib.mkDefault 0;
    keep-outputs = false;
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
      "recursive-nix"
    ];
    extra-system-features = [ "recursive-nix" ];
  };
in
{
  options.nix.settings = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
  };
  config = {
    nix.settings = settings;
    flake.nixosModules.base.nix.settings = settings;

    flake.homeManagerModules.base = _: {
      nix.settings = settings;
    };
  };
}

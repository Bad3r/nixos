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
    # Hard-linking on every store write taxes builds and large substitution
    # runs and serializes on the store lock; the scheduled
    # nix.optimise.automatic run below deduplicates instead.
    auto-optimise-store = lib.mkDefault false;
    cores = lib.mkDefault 0;
    keep-outputs = false;
    experimental-features = [
      "nix-command"
      "flakes"
      # Lix names: `pipe-operator` (singular) gates `|>`; `flake-self-attrs`
      # gates `self.submodules = true` in flake.nix. Only Lix-known names may
      # appear here: the nix.conf check derivation (pkgs.formats.nixConf and
      # the Home Manager equivalent) promotes `nix config show` warnings to
      # errors, so an unknown name fails the system build. The CppNix
      # spelling `pipe-operators` lives in flake.nix#nixConfig and in
      # build.sh NIX_CONFIG, which are not check-phased.
      "pipe-operator"
      "flake-self-attrs"
    ];
  };
in
{
  options.nix.settings = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
  };
  config = {
    nix.settings = settings;
    flake.nixosModules.base.nix = {
      inherit settings;
      # Store deduplication off the critical path; replaces
      # auto-optimise-store (defaults to 03:45 daily).
      optimise.automatic = true;
    };

    flake.homeManagerModules.base = _: {
      nix.settings = settings;
    };
  };
}

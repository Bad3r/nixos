{ lib, config, ... }:
{
  options.nix.settings = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
  };
  config = {
    nix.settings = {
      # Auto-trust flake nixConfig settings (safe for own repositories)
      accept-flake-config = true;
      # Disabled due to upstream nixpkgs warning in make-options-doc
      # See: https://github.com/NixOS/nixpkgs/issues/485682
      abort-on-warn = false;
      # IFD consumers in this repo (mirrors flake.nix#nixConfig):
      #   * nix-doom-emacs-unstraightened: evaluates a JSON manifest produced
      #     by a build derivation.
      #   * modules/csec/wordlists.nix: reads the wordlists store path with
      #     builtins.readDir to auto-discover top-level entries.
      # Update both this comment and flake.nix when adding or removing IFD
      # consumers.
      allow-import-from-derivation = true;
      keep-outputs = false;
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
        "recursive-nix"
      ];
      extra-system-features = [ "recursive-nix" ];
      # Parallel downloads/connections
      # Explicitly set to defaults for clarity, while still allowing host overrides.
      http-connections = lib.mkDefault 25; # default = 25
      max-substitution-jobs = 16; # default = 16 (number of parallel NAR downloads)
      # Use HTTP/2 for downloads
      http2 = true;
      download-buffer-size = 1073741824; # 1GB
    };
    flake.nixosModules.base.nix = {
      inherit (config.nix) settings;
    };

    flake.homeManagerModules.base = _: {
      nix.settings = config.nix.settings;
    };
  };
}

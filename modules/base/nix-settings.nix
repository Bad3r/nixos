{ lib, config, ... }:
{
  options.nix.settings = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
  };
  config = {
    nix.settings = {
      # Auto-trust flake nixConfig settings (safe for own repositories)
      accept-flake-config = true;
      # Treat Nix warnings as errors to maintain code quality
      abort-on-warn = true;
      # Prevent IFD to ensure evaluation purity and build reproducibility
      allow-import-from-derivation = false;
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

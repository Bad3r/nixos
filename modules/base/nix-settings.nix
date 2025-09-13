{ lib, config, ... }:
{
  options.nix.settings = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
  };
  config = {
    nix.settings = {
      keep-outputs = true;
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
      download-buffer-size = 268435456; # 256MB (default is 64MB)
    };
    flake.nixosModules.base.nix = {
      inherit (config.nix) settings;
    };

    flake.homeManagerModules.base = _: {
      nix.settings = config.nix.settings;
    };
  };
}

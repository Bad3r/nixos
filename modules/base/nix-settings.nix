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
      download-buffer-size = 536870912; # 512MB (default is 64MB)
    };
    flake.modules = {
      nixos.base.nix = {
        inherit (config.nix) settings;
      };

      homeManager.base.nix = {
        inherit (config.nix) settings;
      };
    };
  };
}

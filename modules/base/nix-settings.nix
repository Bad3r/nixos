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
    flake.nixosModules.base.nix = {
      inherit (config.nix) settings;
    };

    flake.homeManagerModules.base.nix = {
      inherit (config.nix) settings;
    };
  };
}

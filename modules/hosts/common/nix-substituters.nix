{ config, lib, ... }:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body = {
    nix.settings = {
      substituters = lib.mkAfter [
        "https://cache.nixos.org" # fallback
        "https://cache.garnix.io"
        "https://cache.numtide.com"
        "https://nixpkgs-unfree.cachix.org" # unfree packages (unrar, etc.)
        # nix-community.cachix.org / doom-emacs-unstraightened.cachix.org are
        # appended by modules/apps/doom-emacs.nix when the module is enabled.
      ];
      trusted-public-keys = lib.mkAfter [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      ];
      narinfo-cache-negative-ttl = lib.mkDefault 10800; # 3 hours
      http-connections = lib.mkForce 0; # unlimited
      http2 = lib.mkDefault true;
      download-attempts = lib.mkDefault 1;
      connect-timeout = lib.mkDefault 1;
    };
  };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}

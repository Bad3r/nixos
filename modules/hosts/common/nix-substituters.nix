{ lib, ... }:
let
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

      download-attempts = lib.mkDefault 1;
      connect-timeout = lib.mkDefault 5;
      max-substitution-jobs = lib.mkDefault 32;
      http-connections = lib.mkForce 0; # unlimited
      http2 = lib.mkDefault true;
      narinfo-cache-negative-ttl = lib.mkDefault 10800; # 3 hours
      stalled-download-timeout = lib.mkDefault 900;

    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

{ lib, ... }:
let
  body = {
    nix.settings = {
      # The NixOS module default already contributes https://cache.nixos.org/
      # (trailing slash) and its trusted key. Re-adding the unslashed
      # spelling is not deduplicated (Lix getDefaultSubstituters compares
      # exact URI strings), so it opens a second store against the same host
      # and doubles narinfo misses.
      substituters = lib.mkAfter [
        "https://cache.garnix.io"
        "https://cache.numtide.com"
        "https://nixpkgs-unfree.cachix.org" # unfree packages (unrar, etc.)
        # nix-community.cachix.org / doom-emacs-unstraightened.cachix.org are
        # appended by modules/apps/doom-emacs.nix when the module is enabled.
      ];
      trusted-public-keys = lib.mkAfter [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      ];

      download-attempts = lib.mkDefault 3;
      connect-timeout = lib.mkDefault 30;
      max-substitution-jobs = lib.mkDefault 0; # unlimited
      http-connections = lib.mkDefault 0; # unlimited
      http2 = lib.mkDefault true;
      narinfo-cache-negative-ttl = lib.mkDefault 60;
      stalled-download-timeout = lib.mkDefault 300; # nix default; fail a stalled download instead of freezing the build

    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

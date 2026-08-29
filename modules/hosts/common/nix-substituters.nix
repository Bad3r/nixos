_:
let
  body =
    {
      config,
      hostName,
      lib,
      ...
    }:
    {
      nix.settings = {
        # The NixOS module default already contributes https://cache.nixos.org/
        # (trailing slash) and its trusted key. Re-adding the unslashed
        # spelling is not deduplicated (Lix getDefaultSubstituters compares
        # exact URI strings), so it opens a second store against the same host
        # and doubles narinfo misses.
        substituters = lib.mkAfter [
          "https://cache.numtide.com"
          "https://nixpkgs-unfree.cachix.org" # unfree packages (unrar, etc.)
          # CI-built custom derivations (cache-roots); see
          # docs/reference/binary-cache-coverage.md
          "https://bad3r-nixos.cachix.org"
          # nix-community.cachix.org / doom-emacs-unstraightened.cachix.org are
          # appended by modules/apps/doom-emacs.nix when the module is enabled.
        ];
        trusted-public-keys = lib.mkAfter [
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
          "bad3r-nixos.cachix.org-1:CWwJIEV6kogZP/xZPRXdT6hkKvs84haLxYgK9oF59JE="
        ];

        download-attempts = lib.mkDefault 3;
        connect-timeout = lib.mkDefault 30;
        # max-substitution-jobs has no "auto": each host pins nproc - 1 in its
        # nix-settings.nix next to max-jobs, required by the assertion below.
        # Both Lix and CppNix clamp values below 1 to 1, so 0 would serialize
        # every download rather than lift the limit; http-connections = 0 is
        # the genuine "no limit" value.
        http-connections = lib.mkDefault 0; # unlimited
        http2 = lib.mkDefault true;
        narinfo-cache-negative-ttl = lib.mkDefault 60;
        stalled-download-timeout = lib.mkDefault 300; # nix default; fail a stalled download instead of freezing the build

      };

      # Required rather than given a mkDefault floor: any floor is
      # indistinguishable from a host that chose that number, so a forgotten
      # pin would build green on Lix's compiled-in 16 instead of nproc - 1.
      # Same reasoning as the required firewallDnsInterfaces entry in
      # modules/hosts/common/firewall.nix.
      # Bounds too, not just presence: 0 was this file's own value until this
      # branch, and it is what "unlimited" on the http-connections line above
      # invites. && is lazy, so the comparison is reached only once the key
      # exists, and isInt keeps a "23" typo (plausible beside max-jobs = "auto")
      # on this message rather than on a raw string/integer comparison error.
      assertions = [
        {
          assertion =
            (config.nix.settings ? max-substitution-jobs)
            && lib.isInt config.nix.settings.max-substitution-jobs
            && config.nix.settings.max-substitution-jobs >= 1;
          message =
            "${hostName}: nix.settings.max-substitution-jobs must be an integer >= 1. Pin "
            + "nproc - 1, floored at 1, in modules/${hostName}/nix-settings.nix next to "
            + "max-jobs; the setting has no \"auto\", so an unset host silently falls back to "
            + "Lix's compiled-in 16, and 0 is not \"unlimited\": both Lix and CppNix clamp it "
            + "to 1 and serialize every download.";
        }
      ];
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

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
      assertions = [
        {
          assertion = config.nix.settings ? max-substitution-jobs;
          message =
            "${hostName}: nix.settings.max-substitution-jobs is unset. Pin nproc - 1 in "
            + "modules/${hostName}/nix-settings.nix next to max-jobs; the setting has no "
            + "\"auto\", so an unset host silently falls back to the evaluator's built-in "
            + "value instead of this fleet's convention.";
        }
      ];
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}

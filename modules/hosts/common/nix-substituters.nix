{ lib, rootPath, ... }:
let
  # One substituter conf for the host daemon and for CI: .github/actions/install-lix
  # appends this file to the runner's daemon conf, so a cache-roots build
  # substitutes every root a cache already serves instead of rebuilding the
  # whole set on each push.
  confPath = ".github/actions/install-lix/substituters.conf";
  confValue =
    key:
    let
      prefix = "${key} = ";
      matches = lib.filter (lib.hasPrefix prefix) (
        lib.splitString "\n" (builtins.readFile (rootPath + "/${confPath}"))
      );
    in
    if matches == [ ] then
      throw "${confPath} has no `${prefix}` line, so no value reaches this setting."
    else if builtins.length matches > 1 then
      throw (
        "${confPath} carries ${toString (builtins.length matches)} `${prefix}` lines; keep exactly "
        + "one. nix.conf accepts repeats and the Lix installer keeps the last, so a host would read "
        + "a different value than the CI daemon."
      )
    else
      lib.removePrefix prefix (builtins.head matches);

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
        # nix-community.cachix.org / doom-emacs-unstraightened.cachix.org are
        # appended by modules/apps/doom-emacs.nix when the module is enabled.
        substituters = lib.mkAfter (lib.splitString " " (confValue "extra-substituters"));
        trusted-public-keys = lib.mkAfter (lib.splitString " " (confValue "extra-trusted-public-keys"));

        download-attempts = lib.mkDefault (lib.toInt (confValue "download-attempts"));
        connect-timeout = lib.mkDefault (lib.toInt (confValue "connect-timeout"));
        # max-substitution-jobs has no "auto": each host pins nproc - 1 in its
        # nix-settings.nix next to max-jobs, required by the assertion below.
        # Both Lix and CppNix clamp values below 1 to 1, so 0 would serialize
        # every download rather than lift the limit; http-connections = 0 is
        # the genuine "no limit" value.
        http-connections = lib.mkDefault 0; # unlimited
        http2 = lib.mkDefault true;
        narinfo-cache-negative-ttl = lib.mkDefault 60;
        stalled-download-timeout = lib.mkDefault (lib.toInt (confValue "stalled-download-timeout")); # nix default; fail a stalled download instead of freezing the build

      };

      # Required rather than given a mkDefault floor: any floor is
      # indistinguishable from a host that chose that number, so a forgotten
      # pin would build green on Lix's compiled-in 16 instead of nproc - 1.
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

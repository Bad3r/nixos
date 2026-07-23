{ lib, ... }:
let
  # Canonical extension set for the secrets/ encryption catch-all. The
  # cleartext regression check (sops-cleartext-check.nix) mirrors this list as
  # a literal and asserts it against the generated .sops.yaml, so drift there
  # fails evaluation. The ensure-sops pre-commit filter
  # (modules/meta/pre-commit.nix) mirrors it too (plus the age/enc container
  # formats) but is NOT asserted; update it by hand when this list changes.
  sensitiveExtensions = [
    "yaml"
    "yml"
    "json"
    "env"
    "ini"
    "asc"
    "md"
    "txt"
  ];
in
{
  # Generate the canonical .sops.yaml policy via the files module
  perSystem = _: {
    files.file.".sops.yaml".text = ''
      keys:
        - &host_pub_key age1llvnvaarx3l5kn3t4mgggt9khkrv38v4lxsvdleg2rxxslqf0qxsnq4laf

      creation_rules:
        - path_regex: secrets/act\.yaml
          encrypted_regex: "^(github_token)$"
          key_groups:
            - age:
                - *host_pub_key

        - path_regex: secrets/r2\.env
          key_groups:
            - age:
                - *host_pub_key

        - path_regex: secrets/r2\.yaml
          key_groups:
            - age:
                - *host_pub_key

        - path_regex: secrets/fonts/.+
          key_groups:
            - age:
                - *host_pub_key

        - path_regex: (?i)secrets/.+\.(${lib.concatStringsSep "|" sensitiveExtensions})$
          key_groups:
            - age:
                - *host_pub_key
    '';
  };
}

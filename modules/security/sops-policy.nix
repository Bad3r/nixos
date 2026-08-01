_: {
  # Generate the canonical .sops.yaml policy via the files module
  # Keep this recipient synchronized with hostPubKey in
  # modules/security/sops-cleartext-check.nix. Key Rotation in
  # docs/sops/README.md updates both literals before re-encrypting payloads.
  perSystem = _: {
    files.file.".sops.yaml".text = ''
      keys:
        - &host_pub_key age1llvnvaarx3l5kn3t4mgggt9khkrv38v4lxsvdleg2rxxslqf0qxsnq4laf

      creation_rules:
        - path_regex: secrets/act\.yaml$
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

        # Deny by default. This rule must stay last: SOPS applies the first
        # matching creation rule, and moving it above secrets/act\.yaml would
        # drop that rule's encrypted_regex. The managed-files-synced flake check
        # compares the committed policy with this files-module source byte-for-byte,
        # and secrets-no-cleartext enforces the security contract independently;
        # update both in the same change.
        - path_regex: secrets/.*
          key_groups:
            - age:
                - *host_pub_key
    '';
  };
}

_: {
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

        - path_regex: secrets/.*
          key_groups:
            - age:
                - *host_pub_key
    '';
  };
}

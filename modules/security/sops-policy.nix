_: {
  # Generate the canonical .sops.yaml policy via the files module
  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path_ = ".sops.yaml";
          drv = pkgs.writeText ".sops.yaml" ''
            keys:
              - &owner_bad3r age1xe57ms95l55wscjg2066unpy7quq3j7tnvj74r5d33d8kz9mjf3qr6z5p7
              - &host_primary age1llvnvaarx3l5kn3t4mgggt9khkrv38v4lxsvdleg2rxxslqf0qxsnq4laf

            creation_rules:
              - path_regex: secrets/act\.yaml
                encrypted_regex: "^(github_token)$"
                key_groups:
                  - age:
                      - *owner_bad3r
                      - *host_primary

              - path_regex: secrets/r2\.env
                key_groups:
                  - age:
                      - *owner_bad3r
                      - *host_primary

              - path_regex: secrets/.+\.(yaml|yml|json|env|ini)$
                key_groups:
                  - age:
                      - *owner_bad3r
                      - *host_primary
          '';
        }
      ];
    };
}

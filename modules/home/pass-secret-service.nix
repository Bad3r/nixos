{
  flake.homeManagerModules.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      keyFingerprint =
        # Public key fingerprint; safe to surface, ignored by ripsecrets
        "80CA80DA06B77EE708D57D9B5B92AB136C03BA48";
      keySecret = lib.attrByPath [ "sops" "secrets" "gpg/vx-secret-key" ] null config;
      keyPath = if keySecret == null then null else keySecret.path;
      haveKeyPath = keyPath != null;
    in
    {
      home = {
        packages = lib.mkBefore [ pkgs.pass ];

        activation.importPassGpgKey = lib.mkIf haveKeyPath (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            key_file="${keyPath}"
            if [ -r "$key_file" ]; then
              if ! gpg --batch --list-secret-keys ${keyFingerprint} >/dev/null 2>&1; then
                gpg --batch --yes --import "$key_file"
                echo "5\ny\n" | gpg --batch --yes --command-fd 0 --edit-key ${keyFingerprint} trust quit >/dev/null 2>&1 || true
              fi
            fi
          ''
        );

        activation.initPassStore = lib.mkIf haveKeyPath (
          lib.hm.dag.entryAfter [ "importPassGpgKey" ] ''
            if [ ! -d "$HOME/.password-store" ]; then
              pass init --quiet ${keyFingerprint} || true
            fi
          ''
        );
      };
    };
}

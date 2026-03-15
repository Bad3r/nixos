{
  flake.homeManagerModules.passGpgBootstrap =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      repoGpg = lib.attrByPath [ "home" "repoGpg" ] { } config;
      keyFingerprint = repoGpg.fingerprint or "";
      gpgExe = lib.getExe' pkgs.gnupg "gpg";
      grepExe = lib.getExe' pkgs.gnugrep "grep";
      passExe = lib.getExe' pkgs.pass "pass";
      cutExe = lib.getExe' pkgs.coreutils "cut";
      headExe = lib.getExe' pkgs.coreutils "head";
      sedExe = lib.getExe' pkgs.gnused "sed";
      trExe = lib.getExe' pkgs.coreutils "tr";
      keySecret = lib.attrByPath [ "sops" "secrets" "gpg/vx-secret-key" ] null config;
      keyPath = if keySecret == null then null else keySecret.path;
      haveKeyPath = (repoGpg.available or false) && keyPath != null && keyFingerprint != "";
    in
    {
      home.activation.importPassGpgKey = lib.mkIf haveKeyPath (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          key_file="${keyPath}"
          expected_fingerprint="${keyFingerprint}"
          set -euo pipefail
          if [ ! -r "$key_file" ]; then
            echo "Repository GPG secret $key_file is not readable" >&2
            exit 1
          fi

          actual_fingerprint="$(LC_ALL=C "${gpgExe}" --batch --show-keys --fingerprint "$key_file" | "${grepExe}" 'Key fingerprint =' | "${headExe}" -n 1 | "${cutExe}" -d= -f2 | "${trExe}" -d '[:space:]')"
          if [ -z "$actual_fingerprint" ]; then
            echo "Failed to read fingerprint from $key_file" >&2
            exit 1
          fi
          if [ "$actual_fingerprint" != "$expected_fingerprint" ]; then
            echo "Expected repo GPG fingerprint $expected_fingerprint but found $actual_fingerprint in $key_file" >&2
            exit 1
          fi
          if ! "${gpgExe}" --batch --list-secret-keys "$expected_fingerprint" >/dev/null 2>&1; then
            "${gpgExe}" --batch --yes --import "$key_file"
            if ! echo "5\ny\n" | "${gpgExe}" --batch --yes --command-fd 0 --edit-key "$expected_fingerprint" trust quit >/dev/null; then
              echo "Failed to record ultimate trust for $expected_fingerprint" >&2
              exit 1
            fi
          fi
        ''
      );

      home.activation.initPassStore = lib.mkIf haveKeyPath (
        lib.hm.dag.entryAfter [ "importPassGpgKey" ] ''
          expected_fingerprint="${keyFingerprint}"
          store_dir="$HOME/.password-store"
          gpg_id_file="$store_dir/.gpg-id"
          set -euo pipefail
          needs_init=0
          if [ ! -d "$store_dir" ] || [ ! -f "$gpg_id_file" ]; then
            needs_init=1
          else
            first_fingerprint="$("${sedExe}" -n '1p' "$gpg_id_file")"
            extra_fingerprint="$("${sedExe}" -n '2p' "$gpg_id_file")"
            if [ "$first_fingerprint" != "$expected_fingerprint" ] || [ -n "$extra_fingerprint" ]; then
              needs_init=1
            fi
          fi

          if [ "$needs_init" -eq 1 ]; then
            if ! "${passExe}" init --quiet "$expected_fingerprint"; then
              echo "Failed to initialize pass store with $expected_fingerprint" >&2
              exit 1
            fi
          fi
        ''
      );
    };
}

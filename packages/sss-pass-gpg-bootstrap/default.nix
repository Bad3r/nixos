{
  lib,
  writeShellApplication,
  gnupg,
  pass,
  gnused,
}:

writeShellApplication {
  name = "sss-pass-gpg-bootstrap";

  runtimeInputs = [
    gnupg
    pass
    gnused
  ];

  text = /* bash */ ''
    subcommand="''${1:-}"
    shift || true

    case "$subcommand" in
      import-key)
        key_file="''${1:-}"
        expected_fingerprint="''${2:-}"
        set -euo pipefail

        if [ -z "$key_file" ] || [ -z "$expected_fingerprint" ]; then
          echo "usage: sss-pass-gpg-bootstrap import-key <key-file> <expected-fingerprint>" >&2
          exit 1
        fi
        if [ ! -r "$key_file" ]; then
          echo "Repository GPG secret $key_file is not readable" >&2
          exit 1
        fi

        record_type_target="f"'pr'
        actual_fingerprint="$(
          gpg --batch --quiet --with-colons --import-options show-only --import "$key_file" |
            while IFS=: read -r record_type _ _ _ _ _ _ _ _ fingerprint_value _; do
              if [ "$record_type" = "$record_type_target" ]; then
                printf '%s' "$fingerprint_value"
                break
              fi
            done
        )"
        if [ -z "$actual_fingerprint" ]; then
          echo "Failed to read a fingerprint from $key_file; the file may be malformed or not an OpenPGP secret key" >&2
          exit 1
        fi
        if [ "$actual_fingerprint" != "$expected_fingerprint" ]; then
          echo "Expected repo GPG fingerprint $expected_fingerprint but found $actual_fingerprint in $key_file" >&2
          exit 1
        fi

        if ! gpg --batch --list-secret-keys "$expected_fingerprint" >/dev/null 2>&1; then
          gpg --batch --yes --import "$key_file"
          if ! printf '5\ny\n' | gpg --batch --yes --command-fd 0 --edit-key "$expected_fingerprint" trust quit >/dev/null; then
            echo "Imported $expected_fingerprint but failed to record ultimate trust" >&2
            exit 1
          fi
        fi
        ;;

      init-store)
        expected_fingerprint="''${1:-}"
        store_dir="$HOME/.password-store"
        gpg_id_file="$store_dir/.gpg-id"
        set -euo pipefail

        if [ -z "$expected_fingerprint" ]; then
          echo "usage: sss-pass-gpg-bootstrap init-store <expected-fingerprint>" >&2
          exit 1
        fi

        needs_init=0
        init_reason=""
        if [ ! -d "$store_dir" ]; then
          needs_init=1
          init_reason="password store directory is missing"
        elif [ ! -f "$gpg_id_file" ]; then
          needs_init=1
          init_reason=".gpg-id is missing"
        else
          first_fingerprint="$(sed -n '1p' "$gpg_id_file")"
          extra_fingerprint="$(sed -n '2p' "$gpg_id_file")"
          if [ "$first_fingerprint" != "$expected_fingerprint" ]; then
            needs_init=1
            init_reason=".gpg-id fingerprint $first_fingerprint does not match expected $expected_fingerprint"
          elif [ -n "$extra_fingerprint" ]; then
            needs_init=1
            init_reason=".gpg-id contains multiple fingerprints; expected only $expected_fingerprint"
          fi
        fi

        if [ "$needs_init" -eq 1 ]; then
          echo "Initializing pass store because $init_reason" >&2
          if ! pass init --quiet "$expected_fingerprint"; then
            echo "pass init failed while repairing the store state; verify that $expected_fingerprint is imported and $store_dir is writable" >&2
            exit 1
          fi
        fi
        ;;

      *)
        echo "usage: sss-pass-gpg-bootstrap <import-key|init-store> ..." >&2
        exit 1
        ;;
    esac
  '';

  meta = {
    description = "Bootstrap helper for repo GPG import and pass store initialization";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.mit;
    mainProgram = "sss-pass-gpg-bootstrap";
    platforms = lib.platforms.linux;
  };
}

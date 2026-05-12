{
  lib,
  stdenvNoCC,
  python3,
  sqlite,
  jq,
  pyaescrypt,
}:

let
  pythonEnv = python3.withPackages (ps: [
    ps.boto3
    pyaescrypt
  ]);
in

stdenvNoCC.mkDerivation {
  pname = "duplicati-r2-extract";
  version = "0.1.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/libexec/duplicati-r2-tools $out/bin
    install -Dm0644 $src/duplicati_r2_common.py $out/libexec/duplicati-r2-tools/duplicati_r2_common.py
    install -Dm0755 $src/duplicati_r2_extract.py $out/libexec/duplicati-r2-tools/duplicati_r2_extract.py
    substituteInPlace $out/libexec/duplicati-r2-tools/duplicati_r2_extract.py \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python3'
    ln -s $out/libexec/duplicati-r2-tools/duplicati_r2_extract.py $out/bin/duplicati-r2-extract
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeBuildInputs = [
    sqlite
    jq
    pythonEnv
  ];

  installCheckPhase = ''
    runHook preInstallCheck

    work=$(mktemp -d)

    # Generate a synthetic AES fixture (3 files, sized to exercise the
    # single-block / single-blocklist / multi-blocklist code paths) and a
    # matching schema-v19 SQLite. The generator uses the same pyAesCrypt
    # decryptStream that production code uses, so a successful round-trip
    # validates the whole format implementation end-to-end.
    export FIX_PW=test
    export PYTHONPATH="$src:$out/libexec/duplicati-r2-tools''${PYTHONPATH:+:$PYTHONPATH}"

    fixture="$work/fixture"
    mkdir -p "$fixture"
    db="$work/duplicati-fixture.sqlite"

    ${pythonEnv}/bin/python3 $src/scripts/make_fixture.py \
      --out "$fixture" \
      --db "$db" \
      --passphrase "$FIX_PW"

    bin="$out/bin/duplicati-r2-extract"

    # Single-block file (50 bytes -> 1 content block, BlocksetEntry path).
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output "$work/tiny.out" test /tiny.txt
    test "$(stat -c%s "$work/tiny.out")" -eq 50
    cmp "$work/tiny.out" "$fixture/plaintext/tiny.txt"

    # Multi-block-no-blocklist (4 KiB / 1024 -> 4 BlocksetEntry rows).
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output "$work/medium.out" test /medium.bin
    test "$(stat -c%s "$work/medium.out")" -eq 4096
    cmp "$work/medium.out" "$fixture/plaintext/medium.bin"

    # Single-blocklist file (32 KiB; 32 content blocks land in 1 BlocklistHash row).
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output "$work/single.out" test /single.bin
    test "$(stat -c%s "$work/single.out")" -eq 32768
    cmp "$work/single.out" "$fixture/plaintext/single.bin"

    # Multi-blocklist file (200 KiB; 200 content blocks span 7 BlocklistHash rows).
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output "$work/big.out" test /big.bin
    test "$(stat -c%s "$work/big.out")" -eq 204800
    cmp "$work/big.out" "$fixture/plaintext/big.bin"

    # stdout mode reproduces the file-output bytes.
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output - test /tiny.txt > "$work/tiny.via-stdout"
    cmp "$work/tiny.out" "$work/tiny.via-stdout"

    # JSON summary lands on stderr; plaintext still goes to the sink.
    summary=$( "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --json --output "$work/tiny.j.out" test /tiny.txt 2>&1 >/dev/null )
    echo "$summary" | jq -e '.plaintext_bytes == 50' >/dev/null

    # Glob mode mirrors the snapshot tree under --output-dir for every match.
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --include '*.bin' --output-dir "$work/include-out" test
    test -f "$work/include-out/medium.bin"
    test -f "$work/include-out/single.bin"
    test -f "$work/include-out/big.bin"
    cmp "$work/include-out/medium.bin" "$fixture/plaintext/medium.bin"
    cmp "$work/include-out/single.bin" "$fixture/plaintext/single.bin"
    cmp "$work/include-out/big.bin"    "$fixture/plaintext/big.bin"

    # HMAC corruption in the dblock holding /tiny.txt must surface as
    # EXIT_DATA_ERR (65), not silent data loss. Bit-flip a byte inside the
    # specific dblock that the SQL planner says holds /tiny.txt's content
    # block; this stays deterministic across fixture-generator changes.
    mkdir -p "$work/corrupt"
    cp -r "$fixture"/*.aes "$work/corrupt/"
    tiny_volume=$(sqlite3 "$db" "
      SELECT rv.Name
      FROM File f
        JOIN FilesetEntry fse ON fse.FileID = f.ID
        JOIN BlocksetEntry be ON be.BlocksetID = f.BlocksetID
        JOIN Block b          ON b.ID = be.BlockID
        JOIN Remotevolume rv  ON rv.ID = b.VolumeID
      WHERE f.Path = '/tiny.txt'
      LIMIT 1
    ")
    test -n "$tiny_volume"
    target="$work/corrupt/$tiny_volume"
    test -f "$target"
    printf '\xff' | dd of="$target" bs=1 count=1 seek=200 conv=notrunc 2>/dev/null
    rc=0
    "$bin" --db "$db" --source "file://$work/corrupt" --passphrase-env FIX_PW \
      --cache-dir "$work/cache-corrupt" --output "$work/should-fail" test /tiny.txt 2>/dev/null || rc=$?
    test "$rc" -eq 65 || {
      echo "HMAC corruption should exit 65, got $rc" >&2
      exit 1
    }

    # On HMAC failure the partial output must not survive.
    test ! -e "$work/should-fail" || {
      echo "should-fail must not have a residual partial after EXIT_DATA_ERR" >&2
      exit 1
    }
    test ! -e "$work/should-fail.partial" || {
      echo "must not leave a .partial sidecar after EXIT_DATA_ERR" >&2
      exit 1
    }

    # Missing path -> EXIT_OPEN_ERR (66).
    rc=0
    "$bin" --db "$db" --source "file://$fixture" --passphrase-env FIX_PW \
      --cache-dir "$work/cache" --output "$work/no.out" test /does/not/exist 2>/dev/null || rc=$?
    test "$rc" -eq 66

    # Wrong passphrase -> EXIT_DATA_ERR (65).
    rc=0
    WRONG=banana "$bin" --db "$db" --source "file://$fixture" --passphrase-env WRONG \
      --cache-dir "$work/cache-wrong" --output "$work/wrongpw.out" test /tiny.txt 2>/dev/null || rc=$?
    test "$rc" -eq 65

    rm -rf "$work"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Single-file extract from a Duplicati R2 archive (Cut B)";
    longDescription = ''
      duplicati-r2-extract resolves a path in the per-target Duplicati SQLite,
      fetches only the dblocks containing the file's content blocks from R2
      (or a file:// mirror), decrypts them through the AES Crypt File Format
      wrapper, and writes the plaintext to a destination file, stdout, or an
      output directory in --include glob mode. Encrypted dblocks are cached
      on disk under an LRU policy; plaintext never persists outside the
      operator-chosen sink. HMAC mismatches refuse loudly with a
      data-error exit code.

      This is Cut B of the design recorded in
      docs/drafts/duplicati-r2-readonly-mount-investigation.md.
    '';
    homepage = "https://github.com/Bad3r/nixos";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "duplicati-r2-extract";
  };
}

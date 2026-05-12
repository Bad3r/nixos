{
  lib,
  stdenvNoCC,
  python3,
  sqlite,
  jq,
}:

stdenvNoCC.mkDerivation {
  pname = "duplicati-r2-list";
  version = "0.1.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/libexec/duplicati-r2-tools $out/bin
    install -Dm0644 $src/duplicati_r2_common.py $out/libexec/duplicati-r2-tools/duplicati_r2_common.py
    install -Dm0755 $src/duplicati_r2_list.py $out/libexec/duplicati-r2-tools/duplicati_r2_list.py
    substituteInPlace $out/libexec/duplicati-r2-tools/duplicati_r2_list.py \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
    ln -s $out/libexec/duplicati-r2-tools/duplicati_r2_list.py $out/bin/duplicati-r2-list
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeBuildInputs = [
    sqlite
    jq
  ];

  installCheckPhase = ''
    runHook preInstallCheck

    work=$(mktemp -d)
    db="$work/duplicati-r2-fixture.sqlite"
    sqlite3 "$db" < "$src/test-fixture.sql"

    bin="$out/bin/duplicati-r2-list"

    "$bin" --db "$db" versions test | grep -qE '^ID'
    "$bin" --db "$db" --json versions test | jq -s '.[0].id' >/dev/null

    "$bin" --db "$db" ls test /data | grep -q one.txt
    "$bin" --db "$db" ls --snapshot 1 test /data | grep -q '^dir.*sub/'

    "$bin" --db "$db" stat test /data/one.txt | grep -q '^size: 12B$'
    # Non-canonical input must normalize before exact-match on f.Path.
    "$bin" --db "$db" stat test '//data/./one.txt' | grep -q '^size: 12B$'
    "$bin" --db "$db" ls test '//data/' | grep -q one.txt
    # Directory and symlink entries (BlocksetID -100/-200) must surface via
    # LEFT JOIN to Blockset; INNER JOIN silently drops them.
    "$bin" --db "$db" stat test /data/sub/ | grep -q '^path: /data/sub/$'
    "$bin" --db "$db" stat test /data/link.txt | grep -q '^path: /data/link.txt$'
    # Human-mode stat must render NULL size/hash as `-`, not Python's `None`.
    "$bin" --db "$db" stat test /data/sub/ | grep -q '^size: -$'
    "$bin" --db "$db" stat test /data/sub/ | grep -q '^hash: -$'
    # Slashless directory inputs must still resolve (Duplicati stores the entry
    # with a trailing slash, so the query has to probe both forms).
    "$bin" --db "$db" stat test /data/sub | grep -q '^path: /data/sub/$'

    "$bin" --db "$db" history test /data/one.txt | grep -qE '^ID'
    history_rows=$( "$bin" --db "$db" --json history test /data/one.txt | wc -l )
    test "$history_rows" -eq 2
    history_norm_rows=$( "$bin" --db "$db" --json history test '/data/./one.txt' | wc -l )
    test "$history_norm_rows" -eq 2
    history_dir_rows=$( "$bin" --db "$db" --json history test /data/sub/ | wc -l )
    test "$history_dir_rows" -eq 2
    history_dir_noslash=$( "$bin" --db "$db" --json history test /data/sub | wc -l )
    test "$history_dir_noslash" -eq 2

    "$bin" --db "$db" grep test '*.txt' | grep -q /data/one.txt
    "$bin" --db "$db" grep test --regex '\.log$' | grep -q /data/two.log

    # cmd_ls --json must emit mtime as ISO-8601 (same schema as the other commands).
    "$bin" --db "$db" --json ls test /data | grep -q '"mtime":"2026-'

    # Symlink rows (BlocksetID = -200) must be labelled as "symlink", not "file".
    "$bin" --db "$db" --json ls test /data | grep -q '"name":"link.txt","type":"symlink"'

    # cmd_ls must not emit the listed directory's own entry as an empty-named row.
    # snapshot 2 has no children under /data/sub/, so the listing should be empty.
    sub_ls_rows=$( "$bin" --db "$db" --json ls test /data/sub/ | wc -l )
    test "$sub_ls_rows" -eq 0
    # snapshot 1 has /data/sub/three.txt; the listing must contain exactly that row.
    sub_ls_s1=$( "$bin" --db "$db" --json ls --snapshot 1 test /data/sub/ | wc -l )
    test "$sub_ls_s1" -eq 1
    "$bin" --db "$db" --json ls --snapshot 1 test /data/sub/ | grep -q '"name":"three.txt"'

    if "$bin" --db "$db" stat test /missing.txt 2>/dev/null; then
      echo "stat on missing path should have failed" >&2
      exit 1
    fi

    if "$bin" --db "$db" stat test "" 2>/dev/null; then
      echo "stat on empty path should have failed" >&2
      exit 1
    fi

    # Paths with .. segments must fail loudly rather than resolve to an ancestor.
    if "$bin" --db "$db" stat test '/data/foo/..' 2>/dev/null; then
      echo "stat on path with .. should have failed" >&2
      exit 1
    fi

    if "$bin" --db /dev/null versions test 2>/dev/null; then
      echo "open on /dev/null should have failed" >&2
      exit 1
    fi

    # Exit code contract per docs/duplicati/operations.md:
    #   66 = snapshot id not found (data-not-found family)
    #   64 = timestamp didn't resolve to any snapshot (usage-error family)
    rc=0
    "$bin" --db "$db" ls --snapshot 9999 test /data 2>/dev/null || rc=$?
    test "$rc" -eq 66 || {
      echo "snapshot id not found should exit 66 per docs, got $rc" >&2
      exit 1
    }
    rc=0
    "$bin" --db "$db" ls --snapshot 1900-01-01T00:00:00Z test /data 2>/dev/null || rc=$?
    test "$rc" -eq 64 || {
      echo "timestamp with no matching snapshot should exit 64 per docs, got $rc" >&2
      exit 1
    }

    jq -n --arg state "$work" \
      '{stateDir: $state, targets: {test: {stateDir: $state}}}' \
      > "$work/manifest.json"
    rc=0
    "$bin" --config "$work/manifest.json" versions missing 2>/dev/null || rc=$?
    test "$rc" -eq 64 || {
      echo "unknown target should exit 64 per docs, got $rc" >&2
      exit 1
    }

    # When the manifest is unreadable, the fallback probes the slug-subdir
    # variant first; this is the path reported in the failure message.
    fallback_err=$( "$bin" --config /nonexistent/manifest.json versions test 2>&1 || true )
    echo "$fallback_err" \
      | grep -q 'database not found: /var/lib/duplicati-r2/test/duplicati-r2-test.sqlite'

    rm -rf "$work"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Read-only path and snapshot queries over Duplicati's local SQLite";
    longDescription = ''
      duplicati-r2-list resolves snapshots, directory listings, single-file
      metadata, version history, and path-glob filters against the per-target
      Duplicati SQLite database opened with mode=ro. No R2 fetches and no AES
      decryption: the tool's blast radius is bounded to local SQL reads against
      the live state directory.

      This is Cut A of the design recorded in
      docs/drafts/duplicati-r2-readonly-mount-investigation.md.
    '';
    homepage = "https://github.com/Bad3r/nixos";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "duplicati-r2-list";
  };
}

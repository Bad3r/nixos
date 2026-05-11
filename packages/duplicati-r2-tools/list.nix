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
    install -Dm0755 $src/duplicati_r2_list.py $out/bin/duplicati-r2-list
    substituteInPlace $out/bin/duplicati-r2-list \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'
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

    "$bin" --db "$db" stat test /data/one.txt | grep -q '^size: 12$'

    "$bin" --db "$db" history test /data/one.txt | grep -qE '^ID'
    history_rows=$( "$bin" --db "$db" --json history test /data/one.txt | wc -l )
    test "$history_rows" -eq 2

    "$bin" --db "$db" grep test '*.txt' | grep -q /data/one.txt
    "$bin" --db "$db" grep test --regex '\.log$' | grep -q /data/two.log

    if "$bin" --db "$db" stat test /missing.txt 2>/dev/null; then
      echo "stat on missing path should have failed" >&2
      exit 1
    fi

    if "$bin" --db /dev/null versions test 2>/dev/null; then
      echo "open on /dev/null should have failed" >&2
      exit 1
    fi

    rm -rf "$work"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Read-only path and snapshot queries over Duplicati's local SQLite";
    longDescription = ''
      duplicati-r2-list resolves snapshots, directory listings, single-file
      metadata, version history, and path-glob filters against the per-target
      Duplicati SQLite database opened with mode=ro&immutable=1. No R2 fetches
      and no AES decryption: the tool's blast radius is bounded to local SQL
      reads against the live state directory.

      This is Cut A of the design recorded in
      docs/drafts/duplicati-r2-readonly-mount-investigation.md.
    '';
    homepage = "https://github.com/Bad3r/nixos";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "duplicati-r2-list";
  };
}

/*
  firefoxpwa: DMail installer

  Build logic for the oneshot installer that
  modules/browsers/firefoxpwa/dmail.nix runs as a user service. It lives here
  rather than inline in the module so the same derivation can be built against a
  stub firefoxpwa, which is what the regression check in
  modules/browsers/firefoxpwa/dmail-check.nix does.

  Returns a function: the caller supplies the firefoxpwa package and the runtime
  path of the decrypted URL secret.
*/
{
  lib,
  writeShellApplication,
  jq,
  coreutils,
}:
{
  firefoxpwa,
  urlPath,
  dataDir,
  appName ? "DMail",
  # 0 in the regression check, which needs the retry loop's control flow, not
  # three real 5-second sleeps per run.
  retryDelay ? 5,
}:
writeShellApplication {
  name = "firefoxpwa-install-dmail";
  runtimeInputs = [
    firefoxpwa
    jq
    coreutils
  ];
  text = ''
    url_file=${lib.escapeShellArg urlPath}
    app_name=${lib.escapeShellArg appName}
    # Passed in rather than re-derived from XDG_DATA_HOME: the caller uses this
    # same value for the sops secret path and the 0700 activation step, and a
    # second rule here would put the marker and config.json outside the
    # directory those protect whenever xdg.dataHome is not at its default.
    data_dir=${lib.escapeShellArg dataDir}
    # Exported, not just read: firefoxpwa resolves its own userdata tree from
    # this variable, so pinning it from the value the caller already passed
    # for data_dir makes the binary and this script agree by construction,
    # rather than depending on a systemd unit's Environment= staying in sync
    # with this file from the outside. XDG_DATA_HOME has no equivalent here:
    # system integration resolves it through a different mechanism
    # (directories::BaseDirs), one this script never reads from either.
    export FFPWA_USERDATA="$data_dir"
    config_file="$data_dir/config.json"
    retry_delay=${lib.escapeShellArg (toString retryDelay)}

    # firefoxpwa deserializes start_url into the Rust url crate's Url
    # (native/src/components/site.rs) and serde writes back its normalized
    # form, so config.json can hold https://host/ for a secret that reads
    # https://host. Comparing against a marker this script writes keeps the
    # idempotency check byte-exact instead of racing that normalization.
    applied_file="$data_dir/dmail-applied-url"
    origin_file="$data_dir/dmail-applied-origin"
    # Origin alone does not authenticate identity: a same-named site at the
    # recorded origin is not necessarily the site this script installed.
    # This records which one is, independent of origin bookkeeping.
    ulid_file="$data_dir/dmail-applied-ulid"
    # record_ulid cannot move before the install the way record_origin did:
    # the ulid does not exist until firefoxpwa returns, so a kill in that
    # window (routine: a switch restarts sops-nix, and PartOf stops this
    # unit) or a site_ulid read racing firefoxpwa connector right after
    # install can leave a site this script genuinely installed with no
    # ulid_file. This says an install by this script was in flight, so that
    # state is repaired rather than refused. Cleared on every path that ends
    # one, so an ordinary uninstall never leaves it behind.
    pending_file="$data_dir/dmail-installing"

    if [ ! -r "$url_file" ]; then
      echo "firefoxpwa-dmail: secret not readable at $url_file" >&2
      exit 1
    fi

    url=$(<"$url_file")
    url="''${url//[[:space:]]/}"
    if [ -z "$url" ]; then
      echo "firefoxpwa-dmail: decrypted URL is empty" >&2
      exit 1
    fi

    # Refused rather than installed: url_origin drops userinfo, so the scope
    # derived from it cannot be a prefix of a start URL that keeps it, and
    # site update cannot rewrite scope afterwards. Carrying the credentials in
    # scope instead is not an option: manifest_url is immutable, so they could
    # never be retired by a rotation.
    if [[ $url =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*@ ]]; then
      echo "firefoxpwa-dmail: the decrypted URL in $url_file embeds credentials; store it without them" >&2
      exit 1
    fi

    # firefoxpwa stores the managed site under .sites.<ulid> and the
    # launcher name set with --name lands at .config.name, so a site
    # carrying this name is our install. Emits the ulid, or nothing.
    # Taking the first match inside jq keeps the exit status jq's own:
    # piping to `head -n1` lets head close the pipe first and SIGPIPE jq,
    # which pipefail then reports as failure.
    site_ulid() {
      [ -f "$config_file" ] || return 0
      jq -r --arg n "$app_name" \
        'first((.sites // {}) | to_entries[] | select(.value.config.name == $n) | .key) // empty' \
        "$config_file" 2>/dev/null
    }

    # RFC 3986 3.1: the scheme is case-insensitive, and the authority ends
    # at the first /, ? or #. Userinfo is dropped (3.2.1 puts it before @, and
    # it is not part of an origin): the result feeds --document-url and the
    # embedded manifest, neither of which site update can rewrite, so
    # credentials left there would outlive every rotation. Stripped as a suffix
    # rather than a third group, so nothing depends on how the regex engine
    # splits two adjacent [^/?#] runs. Emits the origin, or nothing.
    url_origin() {
      [[ $1 =~ ^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#]+) ]] || return 0
      printf '%s' "''${BASH_REMATCH[1]}''${BASH_REMATCH[2]##*@}"
    }

    # The marker holds the decrypted secret, so it is created owner-only.
    # Written through a sibling and renamed: truncating in place would leave a
    # partial marker if the write is interrupted, and a truncated URL yields
    # either a wrong origin or none, which the cross-origin guard below reports
    # as a mismatch on every run with no way back.
    record_applied() {
      (
        umask 077
        printf '%s' "$url" >"$applied_file.next"
      )
      mv "$applied_file.next" "$applied_file"
    }

    # Recorded separately because the two are written on different occasions: an
    # install that registers the site and then fails has established the scope
    # but has no applied URL to record, and the secret can rotate before the
    # repair run. Without this the guard below would have nothing to test then.
    record_origin() {
      (
        umask 077
        printf '%s' "$origin" >"$origin_file.next"
      )
      mv "$origin_file.next" "$origin_file"
    }

    # Authenticates the site itself, not just its origin: a same-named site
    # at the recorded origin can still be a different site the browser
    # extension created, one this script never installed and must not adopt.
    record_ulid() {
      (
        umask 077
        printf '%s' "$ulid" >"$ulid_file.next"
      )
      mv "$ulid_file.next" "$ulid_file"
    }

    # Manifest scope is a prefix match and site update cannot rewrite it,
    # so it must be the bare origin: anything longer pushes same-origin
    # navigation and every later URL rotation into the external browser.
    origin=$(url_origin "$url")
    if [ -z "$origin" ]; then
      # Names the file, not the value: this runs in a user unit, so stderr
      # reaches the journal, which outlives and outreaches the 0600 secret.
      echo "firefoxpwa-dmail: cannot derive an origin from the decrypted URL in $url_file" >&2
      exit 1
    fi

    # Already installed. The start URL is read at runtime from the rotating
    # secret, so refresh it in place when the marker drifts instead of
    # leaving the app pinned to the URL captured at first install. A site
    # carrying this name that neither record accounts for is refused rather
    # than refreshed: its scope is unknown, so it cannot be shown to still
    # contain the current URL.
    if ! ulid=$(site_ulid); then
      # Separated from "no site": jq exits non-zero on an unreadable or
      # partially written config.json (firefoxpwa writes it through
      # File::create with no rename, and firefoxpwa connector can be mid-write
      # when this unit runs), and treating that as absent would register a
      # second site under the same name. jq's stderr stays dropped because a
      # parse error echoes back the line it choked on, which is where
      # start_url lives.
      echo "firefoxpwa-dmail: cannot read $config_file; not installing a second '$app_name'" >&2
      exit 1
    fi
    if [ -n "$ulid" ]; then
      # Gated on ulid_file too, not just the URL: without it, a foreign
      # same-named site the browser extension created after an uninstall
      # would silently pass as a no-op whenever the secret has not rotated,
      # the steady state, reporting success on every switch and login while
      # the launcher points at whatever that foreign site carries. A
      # mismatch falls through to the ulid check below, which refuses loudly.
      if [ -r "$ulid_file" ] && [ "$(<"$ulid_file")" = "$ulid" ] \
        && [ -r "$applied_file" ] && [ "$(<"$applied_file")" = "$url" ]; then
        echo "firefoxpwa-dmail: '$app_name' already installed with current URL"
        exit 0
      fi

      # A rotation that crosses to a new origin cannot be applied: scope is
      # fixed at install time, so the new start URL would sit outside it and
      # every navigation would go to the external browser. Refuse loudly rather
      # than let record_applied mark that state as current.
      #
      # Compared against what this script recorded, never against
      # .manifest.scope: firefoxpwa stores the scope through the url crate,
      # which drops a default port, punycodes an IDN host and fills in an empty
      # path, so a raw-against-normalized test refuses same-origin rotations.
      #
      # Uninstalling is the only remedy offered on purpose. Deleting a record
      # would skip the comparison rather than satisfy it, so no record at all is
      # refused too: the site's scope is then unknown, and a secret that rotated
      # since would otherwise be applied and latched.
      # origin_file first: it is written on every success and also when an
      # install registers the site and then fails, so it is never staler than
      # applied_file. Reading applied_file first would let the origin of a site
      # the user has since uninstalled outrank the one just registered, and the
      # refusal would then loop through its own uninstall remedy forever.
      guard_origin=""
      if [ -r "$origin_file" ]; then
        guard_origin=$(<"$origin_file")
      elif [ -r "$applied_file" ]; then
        guard_origin=$(url_origin "$(<"$applied_file")")
      else
        echo "firefoxpwa-dmail: '$app_name' exists but nothing records the origin it was installed at; uninstall the site so this unit can reinstall it" >&2
        exit 1
      fi
      # Origin bookkeeping alone cannot tell this site apart from a
      # different one at the same origin: uninstalling a site does not clear
      # these records, and a same-named site the browser extension later
      # creates would otherwise inherit them. The ulid firefoxpwa assigned
      # this script's own install is the one thing that does.
      if [ ! -r "$ulid_file" ] || [ "$(<"$ulid_file")" != "$ulid" ]; then
        # A pending_file with no ulid_file means an install this script
        # itself started did not finish recording its ulid, not a foreign
        # site: adopt it now instead of refusing a site the unit did
        # install. A mismatched (not just missing) ulid_file is never
        # given this benefit: that is a different, already-identified site.
        if [ -r "$pending_file" ] && [ ! -r "$ulid_file" ]; then
          record_ulid
          rm -f "$pending_file"
        else
          echo "firefoxpwa-dmail: '$app_name' ($ulid) is not the site this unit installed; uninstall it so this unit can reinstall its own" >&2
          exit 1
        fi
      fi
      if [ "''${guard_origin,,}" != "''${origin,,}" ]; then
        echo "firefoxpwa-dmail: rotated URL origin '$origin' does not match the installed origin '$guard_origin'; uninstall the '$app_name' site so this unit can reinstall it at the new origin" >&2
        exit 1
      fi

      echo "firefoxpwa-dmail: refreshing start URL for '$app_name' ($ulid)"
      if firefoxpwa site update "$ulid" --start-url "$url" --no-manifest-updates; then
        record_origin
        record_applied
        echo "firefoxpwa-dmail: updated start URL for '$app_name'"
        exit 0
      fi
      echo "firefoxpwa-dmail: failed to update start URL for '$app_name'" >&2
      exit 1
    fi

    # A data: manifest keeps the install self-contained: firefoxpwa does not
    # have to fetch or parse a manifest from the target site.
    #
    # Nothing here carries the secret. The manifest is embedded verbatim in
    # the manifest URL, which firefoxpwa persists as config.manifest_url,
    # and --document-url lands in config.document_url; site update can
    # rewrite neither, so a token stored in either could never be retired.
    # Both take the origin instead, leaving --start-url below as the only
    # place the secret goes and the only field rotation has to reach.
    # Site::url prefers config.start_url over the manifest's, so the app
    # still opens the full URL.
    manifest=$(jq -nc --arg s "$origin" --arg n "$app_name" \
      '{name: $n, scope: $s, start_url: $s, display: "standalone"}')
    manifest_url="data:application/manifest+json;base64,$(printf '%s' "$manifest" | base64 -w0)"

    # Recorded before the attempt, not after: the origin is already fixed and
    # validated above, and this branch is only reachable when no site exists, so
    # the record cannot be stale relative to a live site. Recording afterwards
    # left a registered site with no record at all when the script was killed
    # mid-install, which the guard above then refuses on every run. A switch
    # restarts sops-nix, and PartOf stops this unit, so that kill is routine.
    record_origin
    (umask 077; : >"$pending_file")

    for attempt in 1 2 3; do
      # The decrypted URL is passed to firefoxpwa on argv, so it is visible in
      # /proc/<pid>/cmdline to any local user while site install or site update
      # runs. firefoxpwa takes the start URL no other way, so this is the one
      # disclosure channel the 0400 secret, 0600 marker, 0700 directory and
      # journal-safe diagnostics do not close.
      if firefoxpwa site install "$manifest_url" \
        --document-url "$origin" \
        --start-url "$url" \
        --name "$app_name"; then
        if ! ulid=$(site_ulid); then
          echo "firefoxpwa-dmail: cannot read $config_file after installing '$app_name'" >&2
          exit 1
        fi
        if [ -z "$ulid" ]; then
          echo "firefoxpwa-dmail: '$app_name' reported installed but is not in $config_file" >&2
          exit 1
        fi
        record_ulid
        rm -f "$pending_file"
        record_applied
        echo "firefoxpwa-dmail: installed '$app_name'"
        exit 0
      fi
      # A failed attempt can still register the site before erroring (for
      # example on desktop integration), so retrying install here would
      # create a second "DMail" entry. Fail without writing the marker: the
      # next activation takes the refresh branch, whose site update re-runs
      # system integration and records the marker only once it succeeds.
      #
      # site_ulid's own failure is separated from "not registered" for the
      # same reason as the check above it: retrying past a config.json read
      # error the script cannot interpret risks the same duplicate.
      if ! ulid=$(site_ulid); then
        echo "firefoxpwa-dmail: cannot read $config_file; not retrying install" >&2
        exit 1
      fi
      if [ -n "$ulid" ]; then
        record_ulid
        rm -f "$pending_file"
        echo "firefoxpwa-dmail: '$app_name' was registered by a failed install; not retrying install, the next activation repairs it with site update" >&2
        exit 1
      fi
      [ "$attempt" -lt 3 ] || break
      echo "firefoxpwa-dmail: install attempt $attempt failed; retrying" >&2
      sleep "$retry_delay"
    done

    # Reached only through the break above, with $ulid last seen empty: no
    # attempt registered a site, so none of the four records can describe
    # one that exists. A stale applied_file or ulid_file left from an earlier
    # install (uninstalling a site does not clear this script's own markers)
    # would otherwise let the elif fallback or the ulid check above
    # authenticate a site this script never installed; a stale pending_file
    # would let that same check adopt a future foreign site instead of
    # refusing it.
    rm -f "$origin_file" "$applied_file" "$ulid_file" "$pending_file"
    echo "firefoxpwa-dmail: install failed after 3 attempts" >&2
    exit 1
  '';
}

/*
  firefoxpwa: Microsoft 365 installer

  Build logic for the oneshot installer that
  modules/browsers/firefoxpwa/m365.nix runs as a user service. It lives here
  rather than inline in the module so the same derivation can be built against
  a stub firefoxpwa, which is what the regression check in
  modules/browsers/firefoxpwa/m365-check.nix does.

  Returns a function: the caller supplies the firefoxpwa package and the app
  table to install.

  Built through ../firefoxpwa-site-installer, which supplies the prelude every
  site installer needs and takes the lock that keeps two of them off
  config.json at once. Only what is specific to this suite lives here.

  Same site bookkeeping as packages/firefoxpwa-dmail-install, minus the parts
  that only a secret needs: the start URLs are public and declared in the Nix
  store, so they are logged, and the records are ordinary 0600-by-directory
  files rather than umask-guarded ones. What this installer adds is the loop:
  each entry is installed independently and a refusal is counted rather than
  raised, so one site that cannot be installed does not cost the others theirs.

  A refusal is counted; a fault is not. The refusals are the states this script
  decides it must not act on (a foreign site under a managed name, a move
  across origins, an install that never registered), and each one leaves the
  entry describable and recoverable. A failed write to a record or to
  config.json is neither, so it aborts the run under errexit instead: the
  records are what authenticate a site on the next run, and continuing past a
  half-written one is how an entry ends up permanently refused.
*/
{
  lib,
  callPackage,
  jq,
}:
let
  mkSiteInstaller = callPackage ../firefoxpwa-site-installer { };
in
{
  firefoxpwa,
  dataDir,
  xdgDataHome,
  apps,
  # 0 in the regression check, which needs the retry loop's control flow, not
  # three real 5-second sleeps per entry.
  retryDelay ? 5,
}:
mkSiteInstaller {
  name = "firefoxpwa-install-m365";
  inherit dataDir xdgDataHome;
  runtimeInputs = [
    firefoxpwa
    jq
  ];
  text = ''
    retry_delay=${lib.escapeShellArg (toString retryDelay)}

    # firefoxpwa stores the managed site under .sites.<ulid> and the launcher
    # name set with --name lands at .config.name, so a site carrying an entry's
    # name is that entry's install. Emits the ulid, or nothing. Taking the
    # first match inside jq keeps the exit status jq's own: piping to `head -n1`
    # lets head close the pipe first and SIGPIPE jq, which pipefail then
    # reports as failure.
    site_ulid() {
      [ -f "$config_file" ] || return 0
      jq -r --arg n "$1" \
        'first((.sites // {}) | to_entries[] | select(.value.config.name == $n) | .key) // empty' \
        "$config_file" 2>/dev/null
    }

    # RFC 3986 3.1: the scheme is case-insensitive, and the authority ends at
    # the first /, ? or #. Userinfo is dropped (3.2.1 puts it before @, and it
    # is not part of an origin). Default ports are omitted and scheme and host
    # case is folded so equivalent origin spellings compare identically.
    # Emits the origin, or nothing.
    url_origin() {
      [[ $1 =~ ^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#]+) ]] || return 0
      local scheme authority
      scheme="''${BASH_REMATCH[1],,}"
      authority="''${BASH_REMATCH[2]##*@}"
      authority="''${authority,,}"
      case "$scheme$authority" in
        https://*:443) authority="''${authority%:443}" ;;
        http://*:80) authority="''${authority%:80}" ;;
      esac
      printf '%s' "$scheme$authority"
    }

    # Written through a sibling and renamed: truncating in place would leave a
    # partial record if the write is interrupted, and a truncated URL yields
    # either a wrong origin or none, which the cross-origin guard below then
    # reports as a mismatch on every run with no way back.
    record() {
      printf '%s' "$2" >"$1.next"
      mv "$1.next" "$1"
    }

    failed=0
    retryable=0
    # Counted here rather than by the caller testing install_app's status: a
    # bash function invoked as the left side of `||` runs its whole body with
    # errexit ignored, and that suppression is inherited by every compound
    # command inside it, so a failed record or config.json read would pass
    # silently and the entry would be reported installed. install_app is called
    # as a plain command instead, which keeps errexit in force for the writes,
    # and the states it decides not to act on land here.
    refuse() {
      echo "firefoxpwa-m365: $1" >&2
      failed=$((failed + 1))
    }

    retry_refusal() {
      refuse "$1"
      retryable=1
    }

    install_app() {
      local key=$1 name=$2 url=$3
      local applied_file="$data_dir/m365-$key-applied-url"
      local origin_file="$data_dir/m365-$key-applied-origin"
      # Origin alone does not authenticate identity: a same-named site at the
      # recorded origin is not necessarily the site this script installed.
      local ulid_file="$data_dir/m365-$key-applied-ulid"
      # Says an install by this script was in flight, so a kill between
      # firefoxpwa registering the site and record below is repaired rather
      # than refused. Cleared on every path that ends one.
      local pending_file="$data_dir/m365-$key-installing"
      local origin ulid guard_origin manifest manifest_url attempt

      # Refused rather than installed: url_origin drops userinfo, so the scope
      # derived from it cannot be a prefix of a start URL that keeps it, and
      # site update cannot rewrite scope afterwards.
      if [[ $url =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*@ ]]; then
        refuse "the start URL for '$name' embeds credentials; declare it without them"
        return
      fi

      # Manifest scope is a prefix match and site update cannot rewrite it, so
      # it must be the bare origin: anything longer pushes same-origin
      # navigation and every later URL change into the external browser.
      origin=$(url_origin "$url")
      if [ -z "$origin" ]; then
        refuse "cannot derive an origin from the start URL '$url' for '$name'"
        return
      fi

      # Separated from "no site": jq exits non-zero on an unreadable or
      # partially written config.json (firefoxpwa writes it through
      # File::create with no rename, and firefoxpwa connector can be mid-write
      # when this unit runs), and treating that as absent would register a
      # second site under the same name.
      if ! ulid=$(site_ulid "$name"); then
        retry_refusal "cannot read $config_file; not installing a second '$name'"
        return
      fi

      if [ -n "$ulid" ]; then
        # The pending record only licenses adopting a site whose identity is
        # not yet recorded. Once ulid_file names this site it has no further
        # job, and a record left behind by a kill between the two would
        # otherwise never be cleared.
        if [ -r "$ulid_file" ] && [ "$(<"$ulid_file")" = "$ulid" ]; then
          rm -f "$pending_file"
        fi

        # Gated on ulid_file too, not just the URL: without it, a foreign
        # same-named site the browser extension created after an uninstall
        # would silently pass as a no-op whenever the declared URL has not
        # changed, the steady state, while the launcher points at whatever that
        # foreign site carries.
        if [ -r "$ulid_file" ] && [ "$(<"$ulid_file")" = "$ulid" ] \
          && [ -r "$applied_file" ] && [ "$(<"$applied_file")" = "$url" ]; then
          return 0
        fi

        # origin_file first: it is written on every success and also when an
        # install registers the site and then fails, so it is never staler than
        # applied_file. No record at all is refused rather than skipped: the
        # site's scope is then unknown, so it cannot be shown to still contain
        # the declared URL.
        guard_origin=""
        if [ -r "$origin_file" ]; then
          guard_origin=$(<"$origin_file")
        elif [ -r "$applied_file" ]; then
          guard_origin=$(url_origin "$(<"$applied_file")")
        else
          refuse "'$name' exists but nothing records the origin it was installed at; uninstall the site so this unit can reinstall it"
          return
        fi

        if [ ! -r "$ulid_file" ] || [ "$(<"$ulid_file")" != "$ulid" ]; then
          # -s, not -r: the pending record is truncated in place rather than
          # renamed into place, so a kill between open and printf leaves an
          # empty, readable file, and an empty one paired with a config.json
          # read racing firefoxpwa connector would otherwise compare "" = ""
          # and adopt regardless. Its content is the manifest_url the attempt
          # used, which only an install through this script's synthetic data:
          # manifest could produce, so matching it authenticates the site
          # whatever state ulid_file is in.
          if [ -s "$pending_file" ] \
            && [ "$(jq -r --arg u "$ulid" '.sites[$u].config.manifest_url // empty' \
                  "$config_file" 2>/dev/null)" = "$(<"$pending_file")" ]; then
            record "$ulid_file" "$ulid"
            rm -f "$pending_file"
          else
            refuse "'$name' ($ulid) is not the site this unit installed; uninstall it so this unit can reinstall its own"
            return
          fi
        fi

        # Compared against what this script recorded, never against
        # .manifest.scope: firefoxpwa stores the scope through the url crate,
        # which drops a default port, punycodes an IDN host and fills in an
        # empty path, so a raw-against-normalized test refuses same-origin
        # changes. Uninstalling is the only remedy offered on purpose: scope is
        # fixed at install time, so the new start URL would sit outside it and
        # every navigation would go to the external browser.
        if [ "''${guard_origin,,}" != "''${origin,,}" ]; then
          refuse "'$name' is installed at '$guard_origin' but is now declared at '$origin'; uninstall the site so this unit can reinstall it at the new origin"
          return
        fi

        echo "firefoxpwa-m365: refreshing start URL for '$name' ($ulid)"
        if firefoxpwa site update "$ulid" --start-url "$url" --no-manifest-updates; then
          record "$origin_file" "$origin"
          record "$applied_file" "$url"
          return 0
        fi
        retry_refusal "failed to update start URL for '$name'"
        return
      fi

      # A rename keeps the key and changes the launcher name, so the lookup
      # above misses the site this key already installed and this branch would
      # register a second one under the new name while overwriting the only
      # record of the first, leaving the original PWA and its .desktop entry
      # with nothing pointing at them. Told apart from the documented uninstall,
      # which leaves the record behind but takes the site with it, by the site
      # still being there.
      if [ -r "$ulid_file" ] && [ -f "$config_file" ]; then
        local recorded
        # jq's failure separated from "no such site", the way the lookup above
        # separates it from "no site": a read racing firefoxpwa connector's own
        # rewrite exits non-zero, and treating that as "the recorded site is
        # gone" drops into the fresh install below and duplicates it. The -f
        # test above keeps a config.json that is gone entirely installing, which
        # is what site_ulid's own [ -f ] does with it.
        if ! recorded=$(jq -r --arg u "$(<"$ulid_file")" \
          'if ((.sites // {}) | has($u)) then "yes" else "" end' "$config_file" 2>/dev/null); then
          retry_refusal "cannot read $config_file; not installing a second '$name'"
          return
        fi
        if [ -n "$recorded" ]; then
          refuse "'$name' is a new name for the site this unit installed as $(<"$ulid_file"); uninstall that site so this unit can reinstall it under the new name"
          return
        fi
      fi

      # A data: manifest keeps the install self-contained: firefoxpwa does not
      # have to fetch or parse a manifest from the target site, which for these
      # apps sits behind a sign-in redirect. Site::url prefers config.start_url
      # over the manifest's, so the app still opens the declared URL.
      manifest=$(jq -nc --arg s "$origin" --arg n "$name" \
        '{name: $n, scope: $s, start_url: $s, display: "standalone"}')
      manifest_url="data:application/manifest+json;base64,$(printf '%s' "$manifest" | base64 -w0)"

      # Recorded before the attempt: this branch is only reachable when no site
      # exists, so the record cannot be stale relative to a live site, while
      # recording afterwards would leave a registered site with no record at
      # all when the script is killed mid-install, which the guard above then
      # refuses on every run.
      record "$origin_file" "$origin"

      for attempt in 1 2 3; do
        # Written before the call: firefoxpwa registers the site through
        # storage.write partway through site install, so a kill during the call
        # leaves a site this script installed with no ulid record.
        printf '%s' "$manifest_url" >"$pending_file"
        if firefoxpwa site install "$manifest_url" \
          --document-url "$origin" \
          --start-url "$url" \
          --name "$name"; then
          if ! ulid=$(site_ulid "$name"); then
            retry_refusal "cannot read $config_file after installing '$name'"
            return
          fi
          if [ -z "$ulid" ]; then
            rm -f "$pending_file"
            retry_refusal "'$name' reported installed but is not in $config_file"
            return
          fi
          record "$ulid_file" "$ulid"
          rm -f "$pending_file"
          record "$applied_file" "$url"
          echo "firefoxpwa-m365: installed '$name'"
          return 0
        fi
        # A failed attempt can still register the site before erroring (for
        # example on desktop integration), so retrying install here would
        # create a second entry under the same name. applied_file is cleared
        # too: a stale record left by an earlier install of this same URL would
        # otherwise satisfy the no-op fast path on the next run and skip the
        # site update this branch defers the repair to.
        if ! ulid=$(site_ulid "$name"); then
          retry_refusal "cannot read $config_file; not retrying '$name'"
          return
        fi
        if [ -n "$ulid" ]; then
          record "$ulid_file" "$ulid"
          rm -f "$pending_file" "$applied_file"
          retry_refusal "'$name' was registered by a failed install; the next run repairs it with site update"
          return
        fi
        rm -f "$pending_file"
        [ "$attempt" -lt 3 ] || break
        echo "firefoxpwa-m365: install attempt $attempt for '$name' failed; retrying" >&2
        sleep "$retry_delay"
      done

      # Reached only through the break above, with $ulid last seen empty: no
      # attempt registered a site, so none of the records can describe one that
      # exists, and a stale one would let a future foreign site pass the
      # identity check above.
      rm -f "$origin_file" "$applied_file" "$ulid_file" "$pending_file"
      retry_refusal "installing '$name' failed after 3 attempts"
    }

    # Unrolled from the app table at build time rather than iterated from an
    # embedded JSON document: the values reach the shell through
    # escapeShellArg, so no field separator can be confused with content, and
    # the store path shows exactly which sites a generation installs.
    ${lib.concatMapStringsSep "\n" (
      app:
      "install_app ${lib.escapeShellArg app.key} ${lib.escapeShellArg app.name} ${lib.escapeShellArg app.url}"
    ) apps}

    if [ "$failed" -ne 0 ]; then
      echo "firefoxpwa-m365: $failed of ${toString (builtins.length apps)} web apps could not be installed" >&2
      # 78 is EX_CONFIG: a refusal needs user action and must remain visible in
      # the journal, but it must not consume the service's restart burst before
      # the user can fix the entry and switch again. Retryable faults keep the
      # ordinary failure status so systemd reruns them with its bounded policy.
      if [ "$retryable" -eq 0 ]; then
        exit 78
      fi
      exit 1
    fi
  '';
}

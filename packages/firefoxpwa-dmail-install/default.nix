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
  appName ? "DMail",
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
    data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa"
    config_file="$data_dir/config.json"

    # firefoxpwa deserializes start_url into the Rust url crate's Url
    # (native/src/components/site.rs) and serde writes back its normalized
    # form, so config.json can hold https://host/ for a secret that reads
    # https://host. Comparing against a marker this script writes keeps the
    # idempotency check byte-exact instead of racing that normalization.
    applied_file="$data_dir/dmail-applied-url"

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
    # at the first /, ? or #. Emits the origin, or nothing.
    url_origin() {
      [[ $1 =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+) ]] || return 0
      printf '%s' "''${BASH_REMATCH[1]}"
    }

    # The marker holds the decrypted secret, so it is created owner-only.
    record_applied() {
      (
        umask 077
        printf '%s' "$url" >"$applied_file"
      )
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
    # installed before the marker existed takes one refresh, then no-ops.
    if ulid=$(site_ulid) && [ -n "$ulid" ]; then
      if [ -r "$applied_file" ] && [ "$(<"$applied_file")" = "$url" ]; then
        echo "firefoxpwa-dmail: '$app_name' already installed with current URL"
        exit 0
      fi

      # A rotation that crosses to a new origin cannot be applied: scope is
      # fixed at install time, so the new start URL would sit outside it and
      # every navigation would go to the external browser. Refuse loudly
      # rather than let record_applied mark that state as current.
      #
      # Compared against the marker, not .manifest.scope: firefoxpwa stores
      # the scope through the url crate, which also drops a default port,
      # punycodes an IDN host and fills in an empty path, so a raw-against-
      # normalized test refuses rotations that are in fact same-origin. Both
      # sides here are secrets this script wrote, so only case can differ.
      if [ -r "$applied_file" ]; then
        applied_origin=$(url_origin "$(<"$applied_file")")
        if [ "''${applied_origin,,}" != "''${origin,,}" ]; then
          echo "firefoxpwa-dmail: rotated URL origin '$origin' does not match the installed origin '$applied_origin'; uninstall the '$app_name' site, or remove $applied_file if it is stale, so this unit can reinstall it" >&2
          exit 1
        fi
      fi

      echo "firefoxpwa-dmail: refreshing start URL for '$app_name' ($ulid)"
      if firefoxpwa site update "$ulid" --start-url "$url" --no-manifest-updates; then
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

    for attempt in 1 2 3; do
      if firefoxpwa site install "$manifest_url" \
        --document-url "$origin" \
        --start-url "$url" \
        --name "$app_name"; then
        record_applied
        echo "firefoxpwa-dmail: installed '$app_name'"
        exit 0
      fi
      # A failed attempt can still register the site before erroring (for
      # example on desktop integration), so retrying install here would
      # create a second "DMail" entry. Fail without writing the marker: the
      # next activation takes the refresh branch, whose site update re-runs
      # system integration and records the marker only once it succeeds.
      if ulid=$(site_ulid) && [ -n "$ulid" ]; then
        echo "firefoxpwa-dmail: '$app_name' was registered by a failed install; not retrying install, the next activation repairs it with site update" >&2
        exit 1
      fi
      echo "firefoxpwa-dmail: install attempt $attempt failed; retrying" >&2
      sleep 5
    done

    echo "firefoxpwa-dmail: install failed after 3 attempts" >&2
    exit 1
  '';
}

{
  lib,
  stdenvNoCC,
  fetchurl,
  bash,
  bubblewrap,
  cacert,
  coreutils,
  git,
}:

let
  version = "0.3.8";
  releaseTag = "v${version}";
  archiveName = "gitlawb-${releaseTag}-x86_64-unknown-linux-musl.tar.gz";
  releaseUrl = "https://github.com/Gitlawb/releases/releases/tag/${releaseTag}";
  archiveUrl = "https://github.com/Gitlawb/releases/releases/download/${releaseTag}/${archiveName}";
  sandboxPath = lib.makeBinPath [
    git
    coreutils
  ];
  caBundle = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in
stdenvNoCC.mkDerivation {
  pname = "gitlawb";
  inherit version;

  src = fetchurl {
    url = archiveUrl;
    hash = "sha256-GW4jeXx+qR7aL5HRf8rtf+W2mttDuHFXJ70Q42JnXP8=";
  };

  dontUnpack = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/gitlawb"

    tmp_extract_dir="$(mktemp -d)"
    tar -xzf "$src" -C "$tmp_extract_dir"

    install -Dm755 "$tmp_extract_dir/gl" "$out/libexec/gitlawb/gl"
    install -Dm755 "$tmp_extract_dir/git-remote-gitlawb" "$out/libexec/gitlawb/git-remote-gitlawb"

    cat > "$out/libexec/gitlawb/run-sandboxed" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail

    raw_binary="$1"
    shift

    if [ "''${GITLAWB_SANDBOX:-0}" = "1" ]; then
      exec "$raw_binary" "$@"
    fi

    if [ -z "''${HOME:-}" ]; then
      echo "gitlawb sandbox wrapper requires HOME to be set" >&2
      exit 1
    fi

    pwd_physical="$(${coreutils}/bin/pwd -P)"

    find_repo_root() {
      local current="$1"
      while true; do
        if [ -e "$current/.git" ]; then
          printf '%s\n' "$current"
          return 0
        fi

        local parent
        parent="$(${coreutils}/bin/dirname "$current")"
        if [ "$parent" = "$current" ]; then
          return 1
        fi
        current="$parent"
      done
    }

    repo_root="$(find_repo_root "$pwd_physical" || true)"

    workspace_source="$pwd_physical"
    sandbox_chdir="/workspace"
    if [ -n "$repo_root" ]; then
      repo_root="$(${coreutils}/bin/realpath "$repo_root")"
      rel_subdir="$(${coreutils}/bin/realpath --relative-to="$repo_root" "$pwd_physical")"
      workspace_source="$repo_root"
      sandbox_chdir="/workspace"
      if [ "$rel_subdir" != "." ]; then
        sandbox_chdir="/workspace/$rel_subdir"
      fi
    fi

    state_dir="''${HOME}/.gitlawb"
    ${coreutils}/bin/mkdir -p "$state_dir"
    ${coreutils}/bin/chmod 700 "$state_dir"

    resolv_conf="$(${coreutils}/bin/readlink -f /etc/resolv.conf)"
    hosts_file="$(${coreutils}/bin/readlink -f /etc/hosts)"

    bwrap_cmd=(
      ${bubblewrap}/bin/bwrap
      --unshare-all
      --share-net
      --new-session
      --die-with-parent
      --hostname gitlawb
      --clearenv
      --dir /workspace
      --dir /home
      --dir /home/gitlawb
      --dir /home/gitlawb/.gitlawb
      --dir /etc
      --ro-bind /nix/store /nix/store
      --bind "$workspace_source" /workspace
      --bind "$state_dir" /home/gitlawb/.gitlawb
      --ro-bind "$resolv_conf" /etc/resolv.conf
      --ro-bind "$hosts_file" /etc/hosts
      --proc /proc
      --dev /dev
      --tmpfs /tmp
      --tmpfs /run
      --setenv HOME /home/gitlawb
      --setenv USER gitlawb
      --setenv LOGNAME gitlawb
      --setenv PATH "${sandboxPath}:${placeholder "out"}/bin"
      --setenv TMPDIR /tmp
      --setenv SSL_CERT_FILE ${caBundle}
      --setenv NIX_SSL_CERT_FILE ${caBundle}
      --setenv XDG_CONFIG_HOME /tmp/xdg-config
      --setenv XDG_DATA_HOME /tmp/xdg-data
      --setenv XDG_STATE_HOME /tmp/xdg-state
      --setenv XDG_CACHE_HOME /tmp/xdg-cache
      --setenv GIT_CONFIG_NOSYSTEM 1
      --setenv GIT_CONFIG_GLOBAL /dev/null
      --setenv GITLAWB_KEY /home/gitlawb/.gitlawb/identity.pem
      --setenv GITLAWB_SANDBOX 1
    )

    if [ -n "''${TERM:-}" ]; then
      bwrap_cmd+=( --setenv TERM "$TERM" )
    fi

    if [ -n "''${LANG:-}" ]; then
      bwrap_cmd+=( --setenv LANG "$LANG" )
    fi

    if [ -n "''${LC_ALL:-}" ]; then
      bwrap_cmd+=( --setenv LC_ALL "$LC_ALL" )
    fi

    bwrap_cmd+=( --setenv GITLAWB_NODE "''${GITLAWB_NODE:-https://node.gitlawb.com}" )

    exec "''${bwrap_cmd[@]}" --chdir "$sandbox_chdir" "$raw_binary" "$@"
    EOF

    cat > "$out/bin/gl" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail
    exec "${placeholder "out"}/libexec/gitlawb/run-sandboxed" "${placeholder "out"}/libexec/gitlawb/gl" "$@"
    EOF

    cat > "$out/bin/git-remote-gitlawb" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail
    exec "${placeholder "out"}/libexec/gitlawb/run-sandboxed" "${placeholder "out"}/libexec/gitlawb/git-remote-gitlawb" "$@"
    EOF

    chmod 755 "$out/libexec/gitlawb/run-sandboxed" "$out/bin/gl" "$out/bin/git-remote-gitlawb"

    runHook postInstall
  '';

  meta = {
    description = "Sandboxed closed-source CLI for the gitlawb decentralized Git network";
    longDescription = ''
      gitlawb is a closed-source CLI for interacting with the gitlawb network.
      This package installs the upstream static Linux binaries and forces all
      runtime execution through a bubblewrap sandbox that limits writable access
      to the current workspace and the dedicated ~/.gitlawb state directory.
    '';
    homepage = "https://gitlawb.com";
    changelog = releaseUrl;
    license = lib.licenses.unfree;
    mainProgram = "gl";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}

{
  baseSettings,
  nixProjectSettings,
  configDir,
  codexPkg,
  lib,
  pkgs,
}:
let
  tomlFormat = pkgs.formats.toml { };
  coreutilsMktemp = lib.getExe' pkgs.coreutils "mktemp";
  coreutilsRm = lib.getExe' pkgs.coreutils "rm";
  coreutilsSha256sum = lib.getExe' pkgs.coreutils "sha256sum";

  baseConfigFile = tomlFormat.generate "codex-config-base" baseSettings;
  nixProjectsFile = tomlFormat.generate "codex-nix-projects" nixProjectSettings;

  tomlMergePython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  tomlMergeScript = pkgs.writeText "codex-merge-config.py" ''
    from pathlib import Path
    import sys
    import tomllib
    import tomlkit


    def load_toml(label: str, path_str: str) -> dict:
        path = Path(path_str)
        if not path.exists():
            return {}
        try:
            raw = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise SystemExit(f"{label}: failed to read {path}: {exc}") from exc
        if not raw.strip():
            return {}
        try:
            return tomllib.loads(raw)
        except tomllib.TOMLDecodeError as exc:
            raise SystemExit(f"{label}: invalid TOML in {path}: {exc}") from exc


    def deep_merge(base: dict, override: dict) -> dict:
        for key, value in override.items():
            current = base.get(key)
            if isinstance(current, dict) and isinstance(value, dict):
                deep_merge(current, value)
            else:
                base[key] = value
        return base


    base_path, nix_projects_path, user_projects_path, out_path = sys.argv[1:5]
    merged = {}
    for label, path in (
        ("base config", base_path),
        ("nix-managed projects", nix_projects_path),
        ("user-managed projects", user_projects_path),
    ):
        deep_merge(merged, load_toml(label, path))

    out_file = Path(out_path)
    try:
        out_file.write_text(tomlkit.dumps(merged), encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"failed to write merged config to {out_file}: {exc}") from exc
  '';

  # Wrapper that assembles config.toml before launching codex.
  # Uses parser-based TOML merge with precedence:
  # base settings < nix-managed projects < user-managed projects.
  # Re-merges only when the input file hashes change.
  codexWrapped = pkgs.writeShellScriptBin "codex" ''
    cfgDir="''${CODEX_HOME:-${configDir}}"
    base="$cfgDir/config.base.toml"
    nixProjects="$cfgDir/projects.nix.toml"
    userProjects="$cfgDir/trusted-projects.toml"
    out="$cfgDir/config.toml"
    mergeStamp="$cfgDir/config.merge.sha256"
    tmpDir="/tmp/agents"
    tmpOut=""
    tmpStamp=""

    mkdir -p "$tmpDir"
    export TMPDIR="$tmpDir"

    cleanupMergeArtifacts() {
      if [ -n "$tmpOut" ] && [ -e "$tmpOut" ]; then
        ${coreutilsRm} -f -- "$tmpOut"
      fi
      if [ -n "$tmpStamp" ] && [ -e "$tmpStamp" ]; then
        ${coreutilsRm} -f -- "$tmpStamp"
      fi
    }

    hashInputs() {
      for path in "$base" "$nixProjects" "$userProjects"; do
        if [ -f "$path" ]; then
          printf 'file\t%s\t' "$path"
          ${coreutilsSha256sum} "$path"
        else
          printf 'missing\t%s\n' "$path"
        fi
      done | ${coreutilsSha256sum} | awk '{print $1}'
    }

    if [ -f "$base" ]; then
      inputHash="$(hashInputs)"
      cachedHash=""
      if [ -f "$mergeStamp" ]; then
        read -r cachedHash < "$mergeStamp" || cachedHash=""
      fi

      if [ ! -s "$out" ] || [ "$cachedHash" != "$inputHash" ]; then
        tmpOut="$(${coreutilsMktemp} "$tmpDir/codex-config.XXXXXXXX.toml")" || {
          echo "codex-wrapper: ERROR: failed to create temporary config file in $tmpDir" >&2
          exit 1
        }
        tmpStamp="$(${coreutilsMktemp} "$tmpDir/codex-config-stamp.XXXXXXXX")" || {
          echo "codex-wrapper: ERROR: failed to create temporary stamp file in $tmpDir" >&2
          exit 1
        }
        trap cleanupMergeArtifacts EXIT INT TERM

        if ${tomlMergePython}/bin/python ${tomlMergeScript} "$base" "$nixProjects" "$userProjects" "$tmpOut"; then
          if [ -s "$tmpOut" ]; then
            if ! printf '%s\n' "$inputHash" > "$tmpStamp"; then
              echo "codex-wrapper: ERROR: failed to write merge stamp to $tmpStamp" >&2
              exit 1
            fi
            mv "$tmpOut" "$out"
            tmpOut=""
            mv "$tmpStamp" "$mergeStamp"
            tmpStamp=""
            trap - EXIT INT TERM
          else
            echo "codex-wrapper: ERROR: merged config is empty or missing at $tmpOut" >&2
            exit 1
          fi
        else
          mergeStatus=$?
          echo "codex-wrapper: ERROR: failed to merge config (exit $mergeStatus)" >&2
          echo "codex-wrapper: ERROR: base=$base nixProjects=$nixProjects userProjects=$userProjects out=$out" >&2
          exit "$mergeStatus"
        fi
      fi
    fi

    exec ${codexPkg}/bin/codex "$@"
  '';
in
{
  inherit
    baseConfigFile
    codexWrapped
    nixProjectsFile
    ;
}

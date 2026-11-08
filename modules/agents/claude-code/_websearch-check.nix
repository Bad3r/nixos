# Activation check that the installed Claude Code still matches what the
# kagi-websearch plugin copies from the built-in WebSearch: its nested request's
# prompts and error record, and the plugin API its tests exercise. bun installs
# the latest Claude Code at activation, outside the flake, so this cannot be a
# flake check like Codex's codex/web-run-contract. A mismatch never blocks
# activation: it leaves a report the plugin shows in the status line.
{
  lib,
  pkgs,
  plugin,
}:
let
  source = builtins.readFile "${plugin}/hooks/register.ts";
  literal =
    name:
    let
      found = builtins.match ''.*const ${name} =[[:space:]]*"([^"]*)";.*'' source;
    in
    assert lib.assertMsg (found != null) "kagi-websearch: register.ts no longer defines ${name}";
    builtins.head found;
  literals = map literal [
    "SYSTEM"
    "ASK"
    "ERROR_PREFIX"
  ];
in
pkgs.writeShellApplication {
  name = "claude-code-websearch-check";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gnugrep
  ];
  text = ''
    claude=$1
    state=''${XDG_STATE_HOME:-}
    [[ $state == /* ]] || state=$HOME/.local/state
    report=$state/kagi-search/claude-code-check.txt

    problems=()
    if binary=$(readlink -e -- "$claude") && [[ -x $binary ]]; then
      # A launcher script (nixpkgs' makeWrapper) holds no strings of its own;
      # the executables it names do.
      scanned=("$binary")
      if [[ $(head -c 2 -- "$binary") == '#!' ]]; then
        while IFS= read -r named; do
          if [[ -f $named && -x $named ]]; then scanned+=("$named"); fi
        done < <(grep -o '/[^[:space:]"'"'"']*' -- "$binary" | sort -u)
      fi
      for text in ${lib.escapeShellArgs literals}; do
        LC_ALL=C grep -qaF -- "$text" "''${scanned[@]}" || problems+=("no longer contains: $text")
      done
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      cp -r ${plugin} "$work/plugin"
      chmod -R u+w "$work/plugin"
      if ! output=$(cd "$work/plugin" && timeout 120 "$binary" plugin test 2>&1); then
        problems+=("claude plugin test failed:" "$(tail -n 20 <<<"$output")")
      fi
    else
      problems+=("no Claude Code executable at $claude")
    fi

    if ((''${#problems[@]})); then
      mkdir -p "''${report%/*}"
      chmod 700 "''${report%/*}"
      {
        "$claude" --version 2>/dev/null || echo "$claude"
        printf '%s\n' "''${problems[@]}"
      } >"$report"
      echo "warning: kagi-websearch: Claude Code no longer matches what the plugin copies; see $report" >&2
    else
      rm -f -- "$report"
    fi
  '';
}

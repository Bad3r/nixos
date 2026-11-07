# The nixos-local Claude Code marketplace (marketplace/), with each enabled
# plugin's command option pointed at its app's executable in the current system
# profile: kagi-websearch's searchCommand at kagi-search, browser-webfetch's
# fetchCommand at browser-fetch. A store path would stay in Claude Code's
# plugin copy, which is keyed on the plugin's version, after a rebuilt app is
# collected. A null app leaves its plugin's option empty.
{
  lib,
  pkgs,
  kagiSearch ? null,
  browserFetch ? null,
}:
let
  point =
    plugin: option: app:
    lib.optionalString (
      app != null
    ) "point ${plugin} ${option} /run/current-system/sw/bin/${app.meta.mainProgram}";
in
pkgs.runCommand "claude-code-nixos-local-marketplace" { nativeBuildInputs = [ pkgs.jq ]; } ''
  cp -r ${./marketplace} "$out"
  chmod -R u+w "$out"
  point() {
    plugin="$out/$1/.claude-plugin/plugin.json"
    jq --arg command "$3" ".userConfig.$2.default = \$command" "$plugin" > plugin.json
    mv plugin.json "$plugin"
  }
  ${point "kagi-websearch" "searchCommand" kagiSearch}
  ${point "browser-webfetch" "fetchCommand" browserFetch}
''

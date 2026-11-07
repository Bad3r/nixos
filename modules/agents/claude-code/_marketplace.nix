# The nixos-local Claude Code marketplace (marketplace/), with the
# kagi-websearch plugin's searchCommand pointed at the kagi-search app.
{
  lib,
  pkgs,
  kagiSearch,
}:
pkgs.runCommand "claude-code-nixos-local-marketplace" { nativeBuildInputs = [ pkgs.jq ]; } ''
  cp -r ${./marketplace} "$out"
  chmod -R u+w "$out"
  plugin="$out/kagi-websearch/.claude-plugin/plugin.json"
  jq --arg command ${lib.getExe kagiSearch} \
    '.userConfig.searchCommand.default = $command' "$plugin" > plugin.json
  mv plugin.json "$plugin"
''

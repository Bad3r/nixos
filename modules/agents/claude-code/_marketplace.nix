# The nixos-local Claude Code marketplace (marketplace/), with each plugin in
# apps (name to { option, package }) having its command option pointed at the
# package's executable in the current system profile. A store path would stay
# in Claude Code's plugin copy, which is keyed on the plugin's version, after
# a rebuilt package is collected. A plugin not in apps keeps its option empty.
{
  lib,
  pkgs,
  osConfig,
}:
let
  localPlugins = lib.filterAttrs (_: plugin: plugin ? commandOption) (import ../_plugins.nix);
  needsCommand =
    key:
    lib.any
      (
        client:
        let
          cfg = osConfig.programs.${client}.extended;
        in
        cfg.enable && (cfg.plugins.${key} or false)
      )
      [
        "claude-code"
        "codex"
      ];
  apps = lib.mapAttrs' (
    key: plugin:
    lib.nameValuePair (lib.removeSuffix "@nixos-local" key) {
      option = plugin.commandOption;
      package = osConfig.programs.${plugin.program}.extended.package;
    }
  ) (lib.filterAttrs (key: _: needsCommand key) localPlugins);
in
pkgs.runCommand "claude-code-nixos-local-marketplace" { nativeBuildInputs = [ pkgs.jq ]; } ''
  cp -r ${./marketplace} "$out"
  chmod -R u+w "$out"
  point() {
    plugin="$out/$1/.claude-plugin/plugin.json"
    jq --arg command "$3" ".userConfig.$2.default = \$command" "$plugin" > plugin.json
    mv plugin.json "$plugin"
  }
  ${lib.concatLines (
    lib.mapAttrsToList (
      plugin: app:
      "point ${plugin} ${app.option} /run/current-system/sw/bin/${app.package.meta.mainProgram}"
    ) apps
  )}
''

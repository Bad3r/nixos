# atuin package the controlled bash records run_command with; null when the atuin app is off.
lib: config:
if lib.attrByPath [ "programs" "atuin" "extended" "enable" ] false config then
  config.programs.atuin.extended.package
else
  null

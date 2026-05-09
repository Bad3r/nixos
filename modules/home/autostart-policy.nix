_: {
  flake.homeManagerModules.base =
    { config, lib, ... }:
    {
      home.activation.cleanForeignAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        autostartDir=${lib.escapeShellArg "${config.xdg.configHome}/autostart"}
        if [ -d "$autostartDir" ]; then
          find -H "$autostartDir" -mindepth 1 -maxdepth 1 -name '*.desktop' \
            \( -type f -o \( -type l ! -lname ${lib.escapeShellArg "${builtins.storeDir}/*"} \) \) \
            -print0 \
          | while IFS= read -r -d "" entry; do
              run rm -f $VERBOSE_ARG -- "$entry"
            done
        fi
      '';
    };
}

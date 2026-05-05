_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.hook-luacheck = pkgs.writeShellApplication {
        name = "hook-luacheck";
        runtimeInputs = [ pkgs.luaPackages.luacheck ];
        text = # bash
          ''
            set -euo pipefail

            if [ "$#" -eq 0 ]; then
              exit 0
            fi

            # --std luajit: Checks code against the LuaJIT standard library.
            #   mpv embeds LuaJIT, so this flag ensures luacheck validates
            #   against the exact set of built-in globals and functions
            #   available at runtime.
            # --globals mp: mp is the mpv Lua API entry point, a global
            #   table that exposes playback control, property access, event
            #   hooks, and logging (mp.get_property, mp.add_hook, mp.msg.*,
            #   etc.). mpv injects it into every script at runtime; it is
            #   never declared in the source file. Without this flag,
            #   luacheck reports every mp.* call as an undefined global
            #   error.
            exec luacheck \
              --std luajit \
              --globals mp \
              "$@"
          '';
      };
    };
}

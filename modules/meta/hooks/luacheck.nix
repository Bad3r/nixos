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

            # --std lua51: Validates against the Lua 5.1 standard library.
            #   mpv embeds LuaJIT, which implements the Lua 5.1 spec, so
            #   lua51 matches the exact set of built-in globals and functions
            #   available at runtime.
            # --globals mp: mp is the mpv Lua API entry point, a global
            #   table that exposes playback control, property access, event
            #   hooks, and logging (mp.get_property, mp.add_hook, mp.msg.*,
            #   etc.). mpv injects it into every script at runtime; it is
            #   never declared in the source file. Without this flag,
            #   luacheck reports every mp.* call as an undefined global
            #   error.
            # --: Terminates the variadic --globals list so the file paths
            #   that follow are not consumed as additional global names.
            exec luacheck \
              --std lua51 \
              --globals mp \
              -- \
              "$@"
          '';
      };
    };
}

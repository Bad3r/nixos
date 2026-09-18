{
  config,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      homeDirectory = "/tmp/zsh-check";

      hm = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
          # The gates that source code at startup. Alias groups only add strings, so their gates stay off.
          osConfig.programs = {
            libnotify.extended.enable = true;
            forgit.extended = {
              enable = true;
              package = pkgs.zsh-forgit;
            };
          };
        };
        modules = [
          config.flake.homeManagerModules.zsh
          {
            home = {
              inherit homeDirectory;
              username = "zsh-check";
              stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
              enableNixpkgsReleaseCheck = false;
            };
          }
        ];
      };

      siteFunctionNames = lib.attrNames hm.config.programs.zsh.siteFunctions;
    in
    {
      # `zsh -n` catches syntax errors; the interactive start catches what only fails at run
      # time: a missing plugin file, a compdef before compinit, an option zsh rejects.
      checks."shell/zsh-startup" =
        pkgs.runCommand "zsh-startup-check"
          {
            # Opts this check into the build step in .github/workflows/check.yml.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [
              pkgs.zsh
              pkgs.libnotify
            ];
          }
          ''
            files=${hm.config.home-files}
            profile=${hm.config.home.path}

            for file in "$files/.zshenv" "$files/.config/zsh/.zshenv" "$files/.config/zsh/.zshrc"; do
              zsh -n "$file"
            done
            for name in ${lib.escapeShellArgs siteFunctionNames}; do
              zsh -n "$profile/share/zsh/site-functions/$name"
            done

            mkdir -p ${homeDirectory}
            cp -rs "$files"/. ${homeDirectory}/
            chmod -R u+w ${homeDirectory}
            HOME=${homeDirectory} NIX_PROFILES="$profile" TERM=xterm-256color \
              zsh -i -c exit 2> startup.log
            if [ -s startup.log ]; then
              cat startup.log >&2
              exit 1
            fi

            touch "$out"
          '';
    };
}

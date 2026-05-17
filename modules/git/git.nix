{ lib, metaOwner, ... }:
{
  flake.homeManagerModules.base =
    {
      config,
      osConfig ? { },
      pkgs,
      ...
    }:
    let
      onePasswordPackage = lib.attrByPath [
        "programs"
        "1password-gui-beta"
        "extended"
        "package"
      ] pkgs._1password-gui osConfig;
      githubUnsignedEmail = "github@unsigned.sh";
      githubUnsignedSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDNTENPappbhPz4AqjvRmWBO0m2oS/mkej/pgN0F6fM";
      gitAllowedSignersPath = "${config.xdg.configHome}/git/allowed_signers";
    in
    {
      xdg.configFile."git/allowed_signers".text = ''
        ${githubUnsignedEmail} ${githubUnsignedSigningKey}
      '';

      programs = {
        git = lib.mkMerge [
          # Base git configuration
          {
            enable = true;

            # Git configuration settings
            settings = {
              # Common aliases for faster workflow
              alias = {
                # Status and info
                st = "status";
                s = "status --short";

                # Branching
                br = "branch";
                co = "checkout";
                cob = "checkout -b";

                # Committing
                ci = "commit";
                cia = "commit --amend";
                cim = "commit -m";

                # Diff
                d = "diff";
                dc = "diff --cached";
                ds = "diff --stat";

                # Log
                l = "log --oneline";
                ll = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
                lg = "log --graph --oneline --decorate --all";

                # Remotes
                f = "fetch";
                fa = "fetch --all";
                p = "push";
                pf = "push --force-with-lease";
                pl = "pull";
                plr = "pull --rebase";

                # Rebasing
                rb = "rebase";
                rbi = "rebase -i";
                rbc = "rebase --continue";
                rba = "rebase --abort";

                # Stash
                sta = "stash";
                stp = "stash pop";
                stl = "stash list";

                # Misc
                cl = "clone";
                sw = "switch";
                swc = "switch -c";
              };

              # Core settings
              core = {
                # editor uses $EDITOR env var (set via default-apps.nix)
                # pager is set by programs.delta when enabled
                whitespace = "trailing-space,space-before-tab";
              };

              # Diff tool uses $DIFFPROG env var (set via default-apps.nix)
              diff.tool = "diffprog";
              difftool.diffprog.cmd = "\${DIFFPROG:-nvim -d} \"$LOCAL\" \"$REMOTE\"";
              difftool.prompt = false;

              # Pull settings
              pull.rebase = false;

              # Push settings
              push.default = "simple";
              push.autoSetupRemote = true;

              # Color settings
              color.ui = true;

              # Diff settings
              diff = {
                algorithm = "histogram";
                colorMoved = "default";
              };

              # Init settings
              init.defaultBranch = "main";

              # Merge settings
              merge.conflictStyle = "zdiff3";

              # Rebase settings
              rebase.autoStash = true;
            };

            # LFS configuration
            lfs = {
              enable = true;
              skipSmudge = false;
            };

            # Global gitignore
            ignores = [
              # OS files
              ".DS_Store"
              "Thumbs.db"

              # Editor files
              "*~"
              "*.swp"
              "*.swo"
              ".*.sw?"
              ".vscode/"
              ".idea/"

              # Build artifacts
              "*.o"
              "*.so"
              "*.a"
              "*.dylib"
              "*.dll"
              "*.exe"

              # Nix
              "result"
              "result-*"

              # Misc
              ".envrc.local"
              ".direnv/"
            ];
          }

          # User identity from owner profile
          {
            settings.user = {
              inherit (metaOwner.git) name;
              email = githubUnsignedEmail;
            };
          }

          # SSH commit and tag signing through 1Password.
          {
            signing = {
              key = githubUnsignedSigningKey;
              signByDefault = true;
              format = "ssh";
              signer = lib.getExe' onePasswordPackage "op-ssh-sign";
            };
            settings.gpg.ssh.allowedSignersFile = gitAllowedSignersPath;
          }
        ];

        # Delta diff viewer (moved from programs.git.delta to programs.delta)
        delta = {
          enable = true;
          options = {
            navigate = true;
            light = false;
            side-by-side = false;
            line-numbers = true;
          };
        };
      };
    };
}

{ lib, ... }:
let
  # Direct import bypasses config evaluation order issues
  owner = import ../../lib/meta-owner-profile.nix;
in
{
  flake.homeManagerModules.base = {
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
              editor = "nvim";
              # pager is set by programs.delta when enabled
              whitespace = "trailing-space,space-before-tab";
            };

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
            inherit (owner.git) name email;
          };
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

{ config, lib, ... }:
let
  inherit (config.flake.lib.meta) owner;
in
{
  flake.homeManagerModules.base = {
    programs = {
      git = {
        enable = true;

        # Git configuration settings
        settings = {
          # User identity from owner metadata
          user = {
            inherit (owner.git) name email;
          };

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
            ca = "commit --amend";
            cane = "commit --amend --no-edit";

            # Logging
            lg = "log --graph --oneline --decorate --all";
            l = "log --pretty=format:'%C(yellow)%h %C(blue)%ad %C(reset)%s%C(red)%d %C(green)%an%C(reset)' --date=short";
            ll = "log --pretty=format:'%C(yellow)%h%C(red)%d %C(reset)%s %C(green)%an %C(blue)%ar' --decorate --numstat";
            lol = "log --graph --decorate --pretty=oneline --abbrev-commit";
            lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";

            # Diffing
            d = "diff";
            ds = "diff --staged";
            dt = "difftool";

            # Stashing
            sl = "stash list";
            sa = "stash apply";
            ss = "stash save";
            sp = "stash pop";

            # Syncing
            f = "fetch";
            fa = "fetch --all";
            pl = "pull";
            ps = "push";
            psu = "push -u origin HEAD";

            # Undoing
            unstage = "reset HEAD --";
            undo = "reset --soft HEAD^";

            # Misc
            last = "log -1 HEAD";
            alias = "!git config --get-regexp ^alias\\. | sed -e s/^alias\\.// -e s/\\ /\\ =\\ /";
            root = "rev-parse --show-toplevel";
          };

          # Default branch name
          init = {
            defaultBranch = "main";
          };

          # Pull/push behavior
          pull = {
            rebase = true; # Always rebase on pull
            ff = "only"; # Fast-forward only when possible
          };

          push = {
            default = "current";
            autoSetupRemote = true; # Auto-setup remote tracking
            followTags = true; # Push tags with commits
          };

          # Rebase configuration
          rebase = {
            autoStash = true; # Auto-stash before rebase
            autoSquash = true; # Auto-squash fixup! commits
          };

          # Merge configuration
          merge = {
            ff = "only"; # Only fast-forward merges by default
            conflictStyle = "diff3"; # Show common ancestor in conflicts
          };

          # Fetch configuration
          fetch = {
            prune = true; # Auto-prune deleted remote branches
            pruneTags = true;
          };

          # Diff configuration
          diff = {
            algorithm = "histogram"; # Better diff algorithm
            colorMoved = "default"; # Highlight moved code
          };

          # URL rewrites for SSH
          url = {
            "ssh://git@github.com/" = {
              insteadOf = "https://github.com/";
            };
          };

          # Core settings
          core = {
            editor = lib.mkDefault "nvim";
            whitespace = "trailing-space,space-before-tab";
            autocrlf = "input"; # Convert CRLF to LF on commit
          };

          # Helpful extras
          help = {
            autocorrect = 10; # Auto-correct typos after 1 second
          };

          # Re-use recorded conflict resolutions
          rerere = {
            enabled = true;
          };

          # GPG signing (disabled by default, enable per-user)
          commit = {
            gpgSign = lib.mkDefault false;
          };

          tag = {
            gpgSign = lib.mkDefault false;
          };
        };

        # Ignore patterns for all repositories
        ignores = [
          # Editor files
          "*~"
          "*.swp"
          "*.swo"
          ".vscode/"
          ".idea/"
          "*.iml"

          # OS files
          ".DS_Store"
          "Thumbs.db"

          # Build artifacts
          "*.o"
          "*.so"
          "*.dylib"
          "*.dll"
          "*.exe"

          # Logs
          "*.log"

          # Direnv
          ".direnv/"
          ".envrc"
        ];
      };

      # Delta diff viewer configuration (separate from git)
      delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
          line-numbers = true;
          # Theme managed by Stylix via terminal colors
          side-by-side = false;

          features = "decorations";
          decorations = {
            commit-decoration-style = "bold yellow box ul";
            file-style = "bold yellow ul";
            file-decoration-style = "none";
            hunk-header-decoration-style = "cyan box";
          };
        };
      };
    };
  };
}

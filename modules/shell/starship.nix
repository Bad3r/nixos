/*
  Package: starship
  Description: Cross-shell prompt written in Rust with configurable modules.
  Homepage: https://starship.rs/
  Documentation: https://starship.rs/config/
  Repository: https://github.com/starship/starship

  Summary:
    * Provides a fast, informative prompt that works with Bash, Zsh, Fish, and other shells.
    * Offers modular configuration for Git status, language runtimes, kubectl context, and system metrics.
    * This configuration provides a developer-focused prompt with Nix, Git, and language indicators.

  Features:
    * Git branch, status, and ahead/behind indicators
    * Nix shell detection with custom symbol
    * Language version indicators (Rust, Python, Node.js, Go)
    * Directory truncation for readable paths
    * Command duration for long-running commands
    * Custom format and styling
*/

{ lib, ... }:
{
  flake.homeManagerModules.base = {
    # Enable Stylix theming for Starship
    stylix.targets.starship.enable = lib.mkDefault true;

    programs.starship = {
      enable = true;

      settings = {
        # Format string defining the prompt layout
        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_status"
          "$nix_shell"
          "$rust"
          "$python"
          "$nodejs"
          "$golang"
          "$c"
          "$docker_context"
          "$kubernetes"
          "$cmd_duration"
          "$line_break"
          "$character"
        ];

        # Add newline between prompts
        add_newline = true;

        # Character module (prompt symbol)
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
          vimcmd_symbol = "[❮](bold green)";
        };

        # Directory module
        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
          fish_style_pwd_dir_length = 1;
          format = "[$path]($style)[$read_only]($read_only_style) ";
          style = "bold cyan";
          read_only = " 󰌾";
          read_only_style = "red";
        };

        # Git branch
        git_branch = {
          symbol = " ";
          format = "[$symbol$branch(:$remote_branch)]($style) ";
          style = "bold purple";
        };

        # Git status
        git_status = {
          format = "([$all_status$ahead_behind]($style) )";
          style = "bold red";
          conflicted = "󰞇\${count} ";
          ahead = "↑\${count} ";
          behind = "↓\${count} ";
          diverged = "↕\${ahead_count}↓\${behind_count} ";
          up_to_date = "✓ ";
          untracked = "?\${count} ";
          stashed = "󰏗\${count} ";
          modified = "!\${count} ";
          staged = "+\${count} ";
          renamed = "»\${count} ";
          deleted = "✘\${count} ";
        };

        # Nix shell indicator
        nix_shell = {
          disabled = false;
          impure_msg = "[impure](bold red)";
          pure_msg = "[pure](bold green)";
          unknown_msg = "[unknown](bold yellow)";
          format = "via [$symbol$state( \\($name\\))]($style) ";
          symbol = " ";
          style = "bold blue";
        };

        # Command duration (only show if > 2 seconds)
        cmd_duration = {
          min_time = 2000;
          format = "took [$duration]($style) ";
          style = "bold yellow";
        };

        # Language modules
        rust = {
          symbol = " ";
          format = "via [$symbol($version )]($style)";
          style = "bold red";
        };

        python = {
          symbol = " ";
          format = "via [$symbol$pyenv_prefix($version )(\\($virtualenv\\) )]($style)";
          style = "bold yellow";
        };

        nodejs = {
          symbol = " ";
          format = "via [$symbol($version )]($style)";
          style = "bold green";
        };

        golang = {
          symbol = " ";
          format = "via [$symbol($version )]($style)";
          style = "bold cyan";
        };

        c = {
          symbol = " ";
          format = "via [$symbol($version(-$name) )]($style)";
          style = "bold blue";
        };

        # Docker context
        docker_context = {
          symbol = " ";
          format = "via [$symbol$context]($style) ";
          style = "bold blue";
        };

        # Kubernetes context
        kubernetes = {
          disabled = false;
          format = "on [󱃾 $context \\($namespace\\)](bold purple) ";
        };

        # Package version (disabled by default - can be slow)
        package = {
          disabled = true;
        };

        # Username (only show if not default user)
        username = {
          disabled = false;
          show_always = false;
          format = "[$user]($style) in ";
          style_user = "bold yellow";
          style_root = "bold red";
        };

        # Hostname (only show in SSH sessions)
        hostname = {
          disabled = false;
          ssh_only = true;
          format = "on [$hostname]($style) ";
          style = "bold green";
        };
      };
    };
  };
}

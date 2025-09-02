{
  flake.modules.homeManager.base = {
    # Enable automatic backup of existing files when Home Manager encounters collisions
    home.activation.backupCollisions = {
      # This script runs before the checkLinkTargets phase
      before = [ "checkLinkTargets" ];
      after = [ ];
      data = ''
        # Create backup directory with timestamp
        backupDir="$HOME/.config/home-manager/backups/$(date +%Y%m%d_%H%M%S)"

        # List of files that might cause collisions
        files=(
          "$HOME/.gtkrc-2.0"
          "$HOME/.mozilla/firefox/profiles.ini"
          "$HOME/.config/gtk-3.0/gtk.css"
          "$HOME/.config/gtk-3.0/settings.ini"
          "$HOME/.config/gtk-4.0/gtk.css"
          "$HOME/.config/gtk-4.0/settings.ini"
          "$HOME/.Xresources"
          "$HOME/.config/kitty/kitty.conf"
        )

        # Check if any files need backing up
        needsBackup=false
        for file in "''${files[@]}"; do
          if [[ -e "$file" && ! -L "$file" ]]; then
            needsBackup=true
            break
          fi
        done

        # Create backup if needed
        if $needsBackup; then
          echo "Backing up existing configuration files to $backupDir"
          mkdir -p "$backupDir"

          for file in "''${files[@]}"; do
            if [[ -e "$file" && ! -L "$file" ]]; then
              # Create parent directory structure in backup
              relPath="''${file#$HOME/}"
              backupFile="$backupDir/$relPath"
              mkdir -p "$(dirname "$backupFile")"

              # Move the file to backup
              echo "  Backing up: $file"
              mv "$file" "$backupFile"
            fi
          done

          echo "Backup completed. Files saved to: $backupDir"
        fi
      '';
    };
  };
}

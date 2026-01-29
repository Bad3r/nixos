/*
  Package: greenclip
  Description: Simple clipboard manager to be integrated with rofi.
  Homepage: https://github.com/erebe/greenclip
  Documentation: https://github.com/erebe/greenclip#readme
  Repository: https://github.com/erebe/greenclip

  Summary:
    * Provides systemd user service for greenclip daemon.
    * Manages greenclip.toml configuration via Home Manager.
    * Stores history in RAM (tmpfs) by default; cleared on reboot.

  Config Options:
    max_history_length: Maximum clipboard entries to retain (default: 50).
    max_selection_size_bytes: Max size per entry; 0 = unlimited (default: 0).
    trim_space_from_selection: Strip leading/trailing whitespace (default: true).
    use_primary_selection_as_input: Merge X primary selection with clipboard (default: false).
    blacklisted_applications: Apps to ignore (e.g., ["KeePassXC"]).
    enable_image_support: Store small images in history (default: true).
    static_history: Permanent entries always available in history.
*/

_: {
  flake.homeManagerModules.apps.greenclip =
    {
      osConfig,
      config,
      lib,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "greenclip" "extended" "enable" ] false osConfig;
      inherit (osConfig.programs.greenclip.extended) package;
      cfg = config.programs.greenclip;

      # Runtime directory (tmpfs) for RAM storage
      runtimeDir = "/run/user/${toString osConfig.users.users.${config.home.username}.uid}";

      # Generate TOML config
      tomlConfig = ''
        [greenclip]
          history_file = "${cfg.historyFile}"
          max_history_length = ${toString cfg.maxHistoryLength}
          max_selection_size_bytes = ${toString cfg.maxSelectionSizeBytes}
          trim_space_from_selection = ${lib.boolToString cfg.trimSpaceFromSelection}
          use_primary_selection_as_input = ${lib.boolToString cfg.usePrimarySelectionAsInput}
          blacklisted_applications = [${
            lib.concatMapStringsSep ", " (s: "\"${s}\"") cfg.blacklistedApplications
          }]
          enable_image_support = ${lib.boolToString cfg.enableImageSupport}
          image_cache_directory = "${cfg.imageCacheDirectory}"
          static_history = [
        ${lib.concatMapStringsSep "\n" (s: "'''${s}''',") cfg.staticHistory}
        ]
      '';
    in
    {
      options.programs.greenclip = {
        historyFile = lib.mkOption {
          type = lib.types.str;
          default = "${runtimeDir}/greenclip.history";
          description = "Path to the clipboard history database.";
        };

        maxHistoryLength = lib.mkOption {
          type = lib.types.ints.positive;
          default = 50;
          description = "Maximum number of clipboard entries to retain.";
        };

        maxSelectionSizeBytes = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          description = "Maximum size in bytes for a single entry. 0 means unlimited.";
        };

        trimSpaceFromSelection = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to trim leading and trailing whitespace from selections.";
        };

        usePrimarySelectionAsInput = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to merge X primary selection with clipboard selection.";
        };

        blacklistedApplications = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "KeePassXC"
            "Bitwarden"
          ];
          description = "Applications whose clipboard content should be ignored.";
        };

        enableImageSupport = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to store small images in clipboard history.";
        };

        imageCacheDirectory = lib.mkOption {
          type = lib.types.str;
          default = "${runtimeDir}/greenclip";
          description = "Directory for caching clipboard images.";
        };

        staticHistory = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "frequently used snippet" ];
          description = "Permanent entries that are always available in clipboard history.";
        };
      };

      config = lib.mkIf nixosEnabled {
        xdg.configFile."greenclip.toml".text = tomlConfig;

        systemd.user.services.greenclip = {
          Unit = {
            Description = "Greenclip clipboard manager daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe package} daemon";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
    };
}

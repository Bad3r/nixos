# XDG MIME Applications helpers
#
# Implements helpers for the freedesktop.org XDG MIME Applications Specification.
# Used by default-apps.nix to register default handlers for MIME types.
#
# Reference: https://specifications.freedesktop.org/mime-apps-spec/latest/
#
# INVARIANT: This module MUST NOT read `config` values - only `lib`.
# Reading config would risk circular imports with consumer modules.
# See: flake-parts docs on dogfooding and circular dependencies.
#
# Usage (in flake-parts module outer scope):
#   { config, ... }:
#   let
#     inherit (config.flake.lib) xdg;
#   in
#   { ... xdg.mime.mkBrowserDefaults "floorp.desktop" ... }
#
# Desktop file mappings are also exported for CI validation:
#   xdg.desktopFiles.browser.floorp = { desktop = "floorp.desktop"; module = "floorp"; };
#
{ lib, ... }:
let
  # Generic helper to generate defaultApplications attrset
  mkDefaults = mimeTypes: desktopFile: lib.genAttrs mimeTypes (_: desktopFile);

  # Canonical MIME types for web browsers per freedesktop.org shared-mime-info
  browserMimeTypes = [
    "text/html"
    "text/xml"
    "application/xhtml+xml"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
  ];

  # MIME types for mail clients
  mailClientMimeTypes = [
    "message/rfc822"
    "x-scheme-handler/mailto"
  ];

  # MIME types for BitTorrent clients
  torrentClientMimeTypes = [
    "application/x-bittorrent"
    "x-scheme-handler/magnet"
  ];

  # MIME types for terminal emulators
  terminalMimeTypes = [
    "application/x-terminal-emulator"
    "x-scheme-handler/terminal"
  ];

  # MIME types for file managers
  fileManagerMimeTypes = [
    "inode/directory"
    "application/x-directory"
  ];

  # MIME types for archive managers
  # Source: org.gnome.FileRoller.desktop (MimeType=...)
  archiveMimeTypes = [
    "application/bzip2"
    "application/gzip"
    "application/vnd.android.package-archive"
    "application/vnd.debian.binary-package"
    "application/vnd.ms-cab-compressed"
    "application/vnd.rar"
    "application/x-7z-compressed"
    "application/x-7z-compressed-tar"
    "application/x-ace"
    "application/x-alz"
    "application/x-apple-diskimage"
    "application/x-ar"
    "application/x-archive"
    "application/x-arj"
    "application/x-brotli"
    "application/x-bzip"
    "application/x-bzip-brotli-tar"
    "application/x-bzip-compressed-tar"
    "application/x-bzip1"
    "application/x-bzip1-compressed-tar"
    "application/x-bzip3"
    "application/x-bzip3-compressed-tar"
    "application/x-cabinet"
    "application/x-cd-image"
    "application/x-chrome-extension"
    "application/x-compress"
    "application/x-compressed-tar"
    "application/x-cpio"
    "application/x-deb"
    "application/x-ear"
    "application/x-gtar"
    "application/x-gzip"
    "application/x-gzpostscript"
    "application/x-java-archive"
    "application/x-lha"
    "application/x-lhz"
    "application/x-lrzip"
    "application/x-lrzip-compressed-tar"
    "application/x-lz4"
    "application/x-lz4-compressed-tar"
    "application/x-lzip"
    "application/x-lzip-compressed-tar"
    "application/x-lzma"
    "application/x-lzma-compressed-tar"
    "application/x-lzop"
    "application/x-ms-dos-executable"
    "application/x-ms-wim"
    "application/x-rar"
    "application/x-rar-compressed"
    "application/x-rpm"
    "application/x-rzip"
    "application/x-rzip-compressed-tar"
    "application/x-source-rpm"
    "application/x-stuffit"
    "application/x-tar"
    "application/x-tarz"
    "application/x-tzo"
    "application/x-war"
    "application/x-xar"
    "application/x-xz"
    "application/x-xz-compressed-tar"
    "application/x-zip"
    "application/x-zip-compressed"
    "application/x-zoo"
    "application/x-zstd-compressed-tar"
    "application/zip"
    "application/zstd"
  ];

  # MIME types for image viewers
  imageViewerMimeTypes = [
    "image/avif"
    "image/bmp"
    "image/gif"
    "image/heic"
    "image/heif"
    "image/jpeg"
    "image/jxl"
    "image/png"
    "image/svg+xml"
    "image/tiff"
    "image/webp"
    "image/x-icon"
    "image/x-portable-anymap"
    "image/x-portable-bitmap"
    "image/x-portable-graymap"
    "image/x-portable-pixmap"
  ];

  # MIME types for document viewers (PDF, EPUB, DjVu, PostScript, comic books)
  documentViewerMimeTypes = [
    "application/epub+zip"
    "application/oxps"
    "application/pdf"
    "application/postscript"
    "application/vnd.comicbook+zip"
    "application/vnd.comicbook-rar"
    "application/vnd.ms-xps"
    "application/x-cbr"
    "application/x-cbz"
    "application/x-cbt"
    "application/x-ext-cbr"
    "application/x-ext-cbz"
    "application/x-fictionbook+xml"
    "image/vnd.djvu"
    "image/vnd.djvu+multipage"
  ];

  # MIME types for audio players
  audioPlayerMimeTypes = [
    "audio/aac"
    "audio/flac"
    "audio/mp4"
    "audio/mpeg"
    "audio/ogg"
    "audio/opus"
    "audio/vorbis"
    "audio/x-flac"
    "audio/x-m4a"
    "audio/x-mp3"
    "audio/x-opus+ogg"
    "audio/x-vorbis+ogg"
    "audio/x-wav"
  ];

  # MIME types for video players
  videoPlayerMimeTypes = [
    "video/3gpp"
    "video/3gpp2"
    "video/mp4"
    "video/mpeg"
    "video/ogg"
    "video/quicktime"
    "video/webm"
    "video/x-flv"
    "video/x-m4v"
    "video/x-matroska"
    "video/x-msvideo"
    "video/x-ogm+ogg"
  ];

  # Desktop file mappings: app key → { desktop file name, app module name }
  # Used by default-apps.nix for MIME configuration and ci.nix for validation
  desktopFiles = {
    browser = {
      brave = {
        desktop = "brave-browser.desktop";
        module = "brave";
      };
      chrome = {
        desktop = "google-chrome.desktop";
        module = "google-chrome";
      };
      chromium = {
        desktop = "chromium-browser.desktop";
        module = "chromium";
      };
      firefox = {
        desktop = "firefox.desktop";
        module = "firefox";
      };
      floorp = {
        desktop = "floorp.desktop";
        module = "floorp";
      };
      librewolf = {
        desktop = "librewolf.desktop";
        module = "librewolf";
      };
      mullvad = {
        desktop = "mullvad-browser.desktop";
        module = "mullvad-browser";
      };
      tor = {
        desktop = "torbrowser.desktop";
        module = "tor-browser";
      };
      ungoogled-chromium = {
        desktop = "chromium-browser.desktop";
        module = "ungoogled-chromium";
      };
    };

    terminal = {
      alacritty = {
        desktop = "Alacritty.desktop";
        module = "alacritty";
      };
      kitty = {
        desktop = "kitty.desktop";
        module = "kitty";
      };
      wezterm = {
        desktop = "org.wezfurlong.wezterm.desktop";
        module = "wezterm";
      };
    };

    mailClient = {
      thunderbird = {
        desktop = "thunderbird.desktop";
        module = "thunderbird";
      };
    };

    torrentClient = {
      qbittorrent = {
        desktop = "org.qbittorrent.qBittorrent.desktop";
        module = "qbittorrent";
      };
    };

    fileManager = {
      dolphin = {
        desktop = "org.kde.dolphin.desktop";
        module = "dolphin";
      };
      nemo = {
        desktop = "nemo.desktop";
        module = "nemo";
      };
      nautilus = {
        desktop = "org.gnome.Nautilus.desktop";
        module = "nautilus";
      };
      thunar = {
        desktop = "thunar.desktop";
        module = "thunar";
      };
    };

    archiveManager = {
      file-roller = {
        desktop = "org.gnome.FileRoller.desktop";
        module = "gnome-file-roller";
      };
    };

    imageViewer = {
      feh = {
        desktop = "feh.desktop";
        module = "feh";
      };
      gwenview = {
        desktop = "org.kde.gwenview.desktop";
        module = "gwenview";
      };
      nsxiv = {
        desktop = "nsxiv.desktop";
        module = "nsxiv";
      };
      sxiv = {
        desktop = "sxiv.desktop";
        module = "sxiv";
      };
    };

    documentViewer = {
      evince = {
        desktop = "org.gnome.Evince.desktop";
        module = "evince";
      };
      okular = {
        desktop = "org.kde.okular.desktop";
        module = "okular";
      };
      zathura = {
        desktop = "org.pwmt.zathura.desktop";
        module = "zathura";
      };
    };

    # Audio and video players share the same apps (mpv, vlc handle both)
    audioPlayer = {
      mpv = {
        desktop = "mpv.desktop";
        module = "mpv";
      };
      vlc = {
        desktop = "vlc.desktop";
        module = "vlc";
      };
    };

    videoPlayer = {
      mpv = {
        desktop = "mpv.desktop";
        module = "mpv";
      };
      vlc = {
        desktop = "vlc.desktop";
        module = "vlc";
      };
    };
  };

  mime = {
    inherit
      mkDefaults
      browserMimeTypes
      mailClientMimeTypes
      torrentClientMimeTypes
      terminalMimeTypes
      fileManagerMimeTypes
      archiveMimeTypes
      imageViewerMimeTypes
      documentViewerMimeTypes
      audioPlayerMimeTypes
      videoPlayerMimeTypes
      ;

    # Category-specific helpers (convenience wrappers around mkDefaults)
    mkBrowserDefaults = mkDefaults browserMimeTypes;
    mkMailClientDefaults = mkDefaults mailClientMimeTypes;
    mkTorrentClientDefaults = mkDefaults torrentClientMimeTypes;
    mkTerminalDefaults = mkDefaults terminalMimeTypes;
    mkFileManagerDefaults = mkDefaults fileManagerMimeTypes;
    mkArchiveManagerDefaults = mkDefaults archiveMimeTypes;
    mkImageViewerDefaults = mkDefaults imageViewerMimeTypes;
    mkDocumentViewerDefaults = mkDefaults documentViewerMimeTypes;
    mkAudioPlayerDefaults = mkDefaults audioPlayerMimeTypes;
    mkVideoPlayerDefaults = mkDefaults videoPlayerMimeTypes;
  };

  defaultAppCategoryMeta = {
    browser = {
      mkMimeDefaults = mime.mkBrowserDefaults;
      defaultValue = "floorp";
      example = "floorp";
      description = ''
        Default web browser for this host.
        Set to null to not configure a default browser via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.BROWSER = name;
        home-manager.sharedModules = [ { home.sessionVariables.BROWSER = name; } ];
      };
    };

    mailClient = {
      mkMimeDefaults = mime.mkMailClientDefaults;
      defaultValue = "thunderbird";
      example = "thunderbird";
      description = ''
        Default mail client for this host.
        Set to null to not configure a default mail client via XDG mimeapps.
      '';
    };

    torrentClient = {
      mkMimeDefaults = mime.mkTorrentClientDefaults;
      defaultValue = "qbittorrent";
      example = "qbittorrent";
      description = ''
        Default BitTorrent client for this host.
        Set to null to not configure a default BitTorrent client via XDG mimeapps.
      '';
    };

    terminal = {
      mkMimeDefaults = mime.mkTerminalDefaults;
      defaultValue = "kitty";
      example = "kitty";
      description = ''
        Default terminal emulator for this host.
        Set to null to not configure a default terminal via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables = {
          TERMINAL = name;
          COLORTERM = "truecolor";
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              TERMINAL = name;
              COLORTERM = "truecolor";
            };
          }
        ];
      };
    };

    fileManager = {
      mkMimeDefaults = mime.mkFileManagerDefaults;
      defaultValue = "nemo";
      example = "nemo";
      description = ''
        Default file manager for this host.
        Set to null to not configure a default file manager via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.FILE_MANAGER = name;
        home-manager.sharedModules = [ { home.sessionVariables.FILE_MANAGER = name; } ];
      };
    };

    archiveManager = {
      mkMimeDefaults = mime.mkArchiveManagerDefaults;
      defaultValue = "file-roller";
      example = "file-roller";
      description = ''
        Default archive manager (zip, tar, 7z, rar, etc.) for this host.
        Set to null to not configure a default archive manager via XDG mimeapps.
      '';
    };

    imageViewer = {
      mkMimeDefaults = mime.mkImageViewerDefaults;
      defaultValue = "nsxiv";
      example = "nsxiv";
      description = ''
        Default image viewer for this host.
        Set to null to not configure a default image viewer via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.IMAGE = name;
        home-manager.sharedModules = [ { home.sessionVariables.IMAGE = name; } ];
      };
    };

    documentViewer = {
      mkMimeDefaults = mime.mkDocumentViewerDefaults;
      defaultValue = "zathura";
      example = "zathura";
      description = ''
        Default document viewer (PDF, EPUB, DjVu, etc.) for this host.
        Set to null to not configure a default document viewer via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.READER = name;
        home-manager.sharedModules = [ { home.sessionVariables.READER = name; } ];
      };
    };

    audioPlayer = {
      mkMimeDefaults = mime.mkAudioPlayerDefaults;
      defaultValue = "mpv";
      example = "mpv";
      description = ''
        Default audio player for this host.
        Set to null to not configure a default audio player via XDG mimeapps.
      '';
    };

    videoPlayer = {
      mkMimeDefaults = mime.mkVideoPlayerDefaults;
      defaultValue = "mpv";
      example = "mpv";
      description = ''
        Default video player for this host.
        Set to null to not configure a default video player via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.VIDEO_PLAYER = name;
        home-manager.sharedModules = [ { home.sessionVariables.VIDEO_PLAYER = name; } ];
      };
    };
  };

  defaultAppEnvOnlyMeta = {
    editor = {
      defaultValue = "nvim";
      example = "nvim";
      description = ''
        Default text editor for this host.
        Sets EDITOR and VISUAL environment variables.
      '';
      extraConfig = value: {
        environment.variables = {
          EDITOR = value;
          VISUAL = value;
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              EDITOR = value;
              VISUAL = value;
            };
          }
        ];
      };
    };

    pager = {
      defaultValue = "less";
      example = "bat";
      description = ''
        Default pager for this host.
        Sets PAGER, MANPAGER, and MANWIDTH environment variables.
      '';
      extraConfig = value: {
        environment.variables = {
          PAGER = value;
          MANPAGER = value;
          MANWIDTH = "120";
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              PAGER = value;
              MANPAGER = value;
              MANWIDTH = "120";
            };
          }
        ];
      };
    };

    diffProgram = {
      defaultValue = "nvim -d";
      example = "nvim -d";
      description = ''
        Default diff program for this host.
        Sets DIFFPROG environment variable (used by pacdiff, etc.).
      '';
      extraConfig = value: {
        environment.variables.DIFFPROG = value;
        home-manager.sharedModules = [ { home.sessionVariables.DIFFPROG = value; } ];
      };
    };

    opener = {
      defaultValue = "xdg-open";
      example = "xdg-open";
      description = ''
        Default generic file opener for this host.
        Sets OPENER environment variable (delegates to XDG MIME handlers).
      '';
      extraConfig = value: {
        environment.variables.OPENER = value;
        home-manager.sharedModules = [ { home.sessionVariables.OPENER = value; } ];
      };
    };
  };
in
{
  flake = {
    lib.xdg = {
      inherit
        desktopFiles
        defaultAppCategoryMeta
        defaultAppEnvOnlyMeta
        mime
        ;
    };
  };
}

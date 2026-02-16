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
in
{
  flake.lib.xdg.desktopFiles = desktopFiles;

  flake.lib.xdg.mime = {
    inherit
      mkDefaults
      browserMimeTypes
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
    mkTerminalDefaults = mkDefaults terminalMimeTypes;
    mkFileManagerDefaults = mkDefaults fileManagerMimeTypes;
    mkArchiveManagerDefaults = mkDefaults archiveMimeTypes;
    mkImageViewerDefaults = mkDefaults imageViewerMimeTypes;
    mkDocumentViewerDefaults = mkDefaults documentViewerMimeTypes;
    mkAudioPlayerDefaults = mkDefaults audioPlayerMimeTypes;
    mkVideoPlayerDefaults = mkDefaults videoPlayerMimeTypes;
  };
}

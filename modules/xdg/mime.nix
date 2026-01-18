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
{ lib, ... }:
let
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

  # MIME types for image viewers
  imageViewerMimeTypes = [
    "image/bmp"
    "image/gif"
    "image/jpeg"
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
in
{
  flake.lib.xdg.mime = {
    inherit
      browserMimeTypes
      terminalMimeTypes
      fileManagerMimeTypes
      imageViewerMimeTypes
      documentViewerMimeTypes
      videoPlayerMimeTypes
      ;

    # Generate defaultApplications attrset for a browser desktop entry
    mkBrowserDefaults = desktopFile: lib.genAttrs browserMimeTypes (_: desktopFile);

    # Generate defaultApplications attrset for a terminal desktop entry
    mkTerminalDefaults = desktopFile: lib.genAttrs terminalMimeTypes (_: desktopFile);

    # Generate defaultApplications attrset for a file manager desktop entry
    mkFileManagerDefaults = desktopFile: lib.genAttrs fileManagerMimeTypes (_: desktopFile);

    # Generate defaultApplications attrset for an image viewer desktop entry
    mkImageViewerDefaults = desktopFile: lib.genAttrs imageViewerMimeTypes (_: desktopFile);

    # Generate defaultApplications attrset for a document viewer desktop entry
    mkDocumentViewerDefaults = desktopFile: lib.genAttrs documentViewerMimeTypes (_: desktopFile);

    # Generate defaultApplications attrset for a video player desktop entry
    mkVideoPlayerDefaults = desktopFile: lib.genAttrs videoPlayerMimeTypes (_: desktopFile);
  };
}

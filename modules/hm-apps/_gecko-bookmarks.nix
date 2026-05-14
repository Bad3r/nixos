/*
  Internal: shared Gecko-browser bookmarks
  Description: Builds the Netscape bookmarks HTML imported by Firefox-family
  browsers. Work URLs are supplied by SOPS placeholders from
  modules/home/gecko-secrets.nix; non-work URLs are intentionally plain.
*/

{ lib }:
let
  inherit (lib) concatStringsSep escapeXML optionalString;

  plaintextUrls = {
    github = "https://github.com/";
    githubPulls = "https://github.com/pulls/inbox";
    notebooklm = "https://notebooklm.google.com/";
    octobox = "https://octobox.io/";
    whatsapp = "https://web.whatsapp.com/";
    youtube = "https://www.youtube.com/?persist_gl=1&gl=US";
    youtubeMusic = "https://music.youtube.com/";
  };

  indent = level: concatStringsSep "" (map (_: "  ") (lib.range 1 level));

  bookmarkToHTML =
    indentLevel: bookmark:
    let
      href = if bookmark.urlIsTemplate or false then bookmark.url else escapeXML bookmark.url;
    in
    ''${indent indentLevel}<DT><A HREF="${href}" ADD_DATE="1" LAST_MODIFIED="1"${
      optionalString (
        bookmark.tags or [ ] != [ ]
      ) " TAGS=\"${escapeXML (concatStringsSep "," bookmark.tags)}\""
    }>${escapeXML bookmark.name}</A>'';

  directoryToHTML =
    indentLevel: directory:
    let
      nameAttrs =
        if directory.toolbar or false then
          ''PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar''
        else
          ">${escapeXML directory.name}";
    in
    ''
      ${indent indentLevel}<DT><H3 ADD_DATE="1" LAST_MODIFIED="1" ${nameAttrs}</H3>
      ${indent indentLevel}<DL><p>
      ${itemsToHTML (indentLevel + 1) directory.bookmarks}
      ${indent indentLevel}</DL><p>'';

  itemToHTML =
    indentLevel: item:
    if item ? url then bookmarkToHTML indentLevel item else directoryToHTML indentLevel item;

  itemsToHTML = indentLevel: items: concatStringsSep "\n" (map (itemToHTML indentLevel) items);

  mkBookmarks = workUrls: [
    {
      name = "NotebookLM";
      url = plaintextUrls.notebooklm;
      tags = [ "AI" ];
    }
    {
      name = "YouTube";
      url = plaintextUrls.youtube;
      tags = [ "Media" ];
    }
    {
      name = "YT Music";
      url = plaintextUrls.youtubeMusic;
      tags = [ "Media" ];
    }
    {
      name = "Bookmarks Toolbar";
      toolbar = true;
      bookmarks = [
        {
          name = "Work";
          bookmarks = [
            {
              name = "Outlook";
              url = workUrls.outlook;
              urlIsTemplate = true;
              tags = [ "Work" ];
            }
            {
              name = "Teams";
              url = workUrls.teams;
              urlIsTemplate = true;
              tags = [ "Work" ];
            }
            {
              name = "Deem Mail";
              url = workUrls.deemMail;
              urlIsTemplate = true;
              tags = [ "Work" ];
            }
            {
              name = "WhatsApp";
              url = plaintextUrls.whatsapp;
              tags = [ "Social" ];
            }
          ];
        }
        {
          name = "Dev";
          bookmarks = [
            {
              name = "GitHub";
              url = plaintextUrls.github;
              tags = [ "Dev" ];
            }
            {
              name = "GitHub PRs";
              url = plaintextUrls.githubPulls;
              tags = [ "Dev" ];
            }
            {
              name = "Octobox";
              url = plaintextUrls.octobox;
              tags = [ "Dev" ];
            }
          ];
        }
      ];
    }
  ];
in
{
  inherit plaintextUrls;

  settings =
    bookmarksFile:
    lib.optionalAttrs (bookmarksFile != null) {
      "browser.bookmarks.file" = bookmarksFile;
      "browser.places.importBookmarksHTML" = true;
    };

  html =
    workUrls:
    let
      bookmarkEntries = itemsToHTML 1 (mkBookmarks workUrls);
    in
    ''
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <!-- This is an automatically generated file.
        It will be read and overwritten.
        DO NOT EDIT! -->
      <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
      <TITLE>Bookmarks</TITLE>
      <H1>Bookmarks Menu</H1>
      <DL><p>
      ${bookmarkEntries}
      </DL>
    '';
}

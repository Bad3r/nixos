/*
  firefoxpwa: Microsoft 365 web app catalog

  Default for programs.firefoxpwa.m365.apps in ./apps.nix, and the fixture
  ./m365-check.nix asserts against, so both move together.

  Start URLs are bare origins. The installed manifest scope is the origin (see
  packages/firefoxpwa-m365-install), and the landing paths Microsoft redirects
  to are locale- or tenant-dependent (/en-us/, /mail/, /tasks/), so pinning one
  ages out while the origin does not.

  Left out on purpose, all verified 2026-08-04:
    * teams.cloud.microsoft redirects to /v2/unsupported-browser on Gecko.
    * visio.cloud.microsoft redirects to m365.cloud.microsoft, a different
      origin, so it would leave its own scope on first load.
    * clipchamp.cloud.microsoft does not resolve.
*/
[
  {
    key = "m365";
    name = "Microsoft 365";
    url = "https://m365.cloud.microsoft/";
  }
  {
    key = "word";
    name = "Word";
    url = "https://word.cloud.microsoft/";
  }
  {
    key = "excel";
    name = "Excel";
    url = "https://excel.cloud.microsoft/";
  }
  {
    key = "powerpoint";
    name = "PowerPoint";
    url = "https://powerpoint.cloud.microsoft/";
  }
  {
    key = "outlook";
    name = "Outlook";
    url = "https://outlook.cloud.microsoft/";
  }
  {
    key = "onenote";
    name = "OneNote";
    url = "https://onenote.cloud.microsoft/";
  }
  {
    key = "onedrive";
    name = "OneDrive";
    url = "https://onedrive.cloud.microsoft/";
  }
]

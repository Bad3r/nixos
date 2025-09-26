/*
  Package: circumflex
  Description: Terminal user interface for browsing Hacker News with rich navigation and offline history.
  Homepage: https://github.com/bensadeh/circumflex
  Documentation: https://github.com/bensadeh/circumflex#readme
  Repository: https://github.com/bensadeh/circumflex

  Summary:
    * Presents Hacker News front-page categories, comments, and articles in a keyboard-driven TUI with syntax highlighting and emoji support.
    * Keeps local history and favorites lists so you can revisit stories or resume comment threads easily.

  Options:
    clx add <ID>: Mark a story or comment as a favorite by numeric item ID.
    clx comments <ID>: Jump directly to the comment thread for a specific item.
    --categories <list>: Customize the sections displayed in the header (default `top,best,ask,show`).
    --plain-headlines: Disable syntax highlighting for headlines in low-color terminals.
    --auto-expand: Automatically expand all replies when entering a comment section.

  Example Usage:
    * `clx` — Launch the interactive TUI and browse top and best stories.
    * `clx comments 42133706` — Open the discussion for item 42133706 directly.
    * `clx url https://example.com/post` — Render an article in reader mode inside the terminal.
*/

{
  flake.nixosModules.apps.circumflex =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.circumflex ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.circumflex ];
    };
}

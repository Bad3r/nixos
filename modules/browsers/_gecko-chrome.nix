/*
  Internal: shared Gecko-browser chrome stylesheet
  Description: userChrome.css and userContent.css payloads applied to every
  gecko browser profile via _gecko-mk-profile.nix. Loading requires the
  `toolkit.legacyUserProfileCustomizations.stylesheets` pref, which
  _gecko-prefs.nix enables.

  Notes:
    * The dotfiles file opens with an invalid "# Font Settings" line. The
      imported stylesheet keeps that font-family rule disabled with a CSS
      comment so the inert behavior is explicit; activating it is a separate
      decision, not part of this import.
    * The dotfiles `chrome/icons/*.svg` assets are referenced by no rule in
      this stylesheet and are intentionally not copied.
*/

_: {
  userChrome = builtins.readFile ./gecko-chrome/userChrome.css;
  userContent = builtins.readFile ./gecko-chrome/userContent.css;
}

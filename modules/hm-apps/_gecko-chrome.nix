/*
  Internal: shared Gecko-browser chrome stylesheet
  Description: userChrome.css payload applied to every Firefox/LibreWolf
  profile via _gecko-mk-profile.nix. Loading requires the
  `toolkit.legacyUserProfileCustomizations.stylesheets` pref, which
  _gecko-prefs.nix already enables.

  Provenance: gecko-chrome/userChrome.css is imported from
  `.mozilla/firefox/Bad3r/chrome/userChrome.css` at
  Bad3r/dotfiles@c2ae2c0ba55c7f804cd0ec0d3602a951c509f620, with whitespace
  normalized by the repo formatter; it is token-identical to the source.

  Notes:
    * The dotfiles file opens with an invalid "# Font Settings" line, which
      CSS parses into the never-matching selector `#Font Settings *` (the
      formatter writes it that way explicitly). The font-family rule under
      it has therefore always been inert; activating it is a separate
      decision, not part of this import.
    * The dotfiles `userContent.css` is empty at the inspected revision and
      is intentionally not recreated.
    * The dotfiles `chrome/icons/*.svg` assets are referenced by no rule in
      this stylesheet and are intentionally not copied.
*/

_: {
  userChrome = builtins.readFile ./gecko-chrome/userChrome.css;
}

/*
  Internal: shared Gecko-browser chrome stylesheet
  Description: userChrome.css payload applied to every Firefox/LibreWolf
  profile via _gecko-mk-profile.nix. Loading requires the
  `toolkit.legacyUserProfileCustomizations.stylesheets` pref, which
  _gecko-prefs.nix already enables.

  Provenance: gecko-chrome/userChrome.css is imported from
  `.mozilla/firefox/Bad3r/chrome/userChrome.css` at
  Bad3r/dotfiles@c2ae2c0ba55c7f804cd0ec0d3602a951c509f620, with whitespace
  normalized by the repo formatter, the inert font block converted to an
  explicit CSS comment, and hardcoded menu colors replaced with Firefox theme
  variables so Stylix remains the color owner.

  Notes:
    * The dotfiles file opens with an invalid "# Font Settings" line. The
      imported stylesheet keeps that font-family rule disabled with a CSS
      comment so the inert behavior is explicit; activating it is a separate
      decision, not part of this import.
    * The dotfiles `userContent.css` is empty at the inspected revision and
      is intentionally not recreated.
    * The dotfiles `chrome/icons/*.svg` assets are referenced by no rule in
      this stylesheet and are intentionally not copied.
*/

_: {
  userChrome = builtins.readFile ./gecko-chrome/userChrome.css;
}

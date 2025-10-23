/*
  Package: starship
  Description: Cross-shell prompt with rich contextual information.
  Homepage: https://starship.rs/
  Documentation: https://starship.rs/config/
  Repository: https://github.com/starship/starship

  Summary:
    * Provides fast, configurable shell prompts for Bash, Zsh, Fish, and more.
    * Displays contextual data (Git status, language runtimes, time, battery) in a single line.

  Example Usage:
    * `starship preset nerd-font-symbols -o ~/.config/starship.toml` — Apply the Nerd Font preset.
    * `starship explain` — Show how the prompt is rendered for debugging configurations.
*/

{
  flake.homeManagerModules.apps.starship = _: {
    programs.starship.enable = true;
  };
}

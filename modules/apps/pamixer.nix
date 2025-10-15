/*
  Package: pamixer
  Description: PulseAudio/pipewire-pulse command-line mixer with human-friendly controls.
  Homepage: https://github.com/cdemoulins/pamixer
  Documentation: https://github.com/cdemoulins/pamixer#usage
  Repository: https://github.com/cdemoulins/pamixer

  Summary:
    * Offers easy CLI access to PulseAudio volume controls, mute toggles, and sink/source selection for scripting or keybindings.
    * Supports incremental adjustments, setting absolute levels, listing sinks, and managing default devices.

  Options:
    pamixer --get-volume: Print the current volume of the default sink.
    pamixer --set-volume <percent>: Set volume to a specific level.
    pamixer --increase/--decrease <value>: Adjust volume relative to current level.
    pamixer --toggle-mute [--source]: Toggle mute status for sinks or sources.
    pamixer --list-sinks/--list-sources: Enumerate available audio devices.

  Example Usage:
    * `pamixer --increase 5` — Raise the default sink volume by 5%.
    * `pamixer --set-volume 30 --sink 1` — Set sink #1 to 30% volume explicitly.
    * `pamixer --toggle-mute` — Toggle mute state via a keybinding script.
*/

{
  flake.nixosModules.apps.pamixer =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [
        (_final: prev: {
          pamixer = prev.pamixer.overrideAttrs (old: {
            # pamixer 1.6 uses ICU helpers that depend on std::u16string_view (C++17).
            mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dcpp_std=c++17" ];
          });
        })
      ];

      environment.systemPackages = [ pkgs.pamixer ];
    };
}

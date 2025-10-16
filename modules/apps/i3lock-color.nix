/*
  Package: i3lock-color
  Description: Fork of i3lock with color customizations, key indicators, and background effects.
  Homepage: https://github.com/Raymo111/i3lock-color
  Documentation: https://github.com/Raymo111/i3lock-color#usage
  Repository: https://github.com/Raymo111/i3lock-color

  Summary:
    * Extends the classic i3lock screen locker with theming options, image backgrounds, blur effects, and indicator styling.
    * Useful for Wayland/X11 setups (via X) that want a simple locker with aesthetic enhancements.

  Options:
    -i <image>: Use an image as the lock screen background.
    -c <rrggbb>: Set a solid color background.
    -B <radius>: Enable Gaussian blur with specified sigma applied to the background image.
    --indicator: Show the unlock indicator circle.
    --inside-color/--ring-color/--line-color <rrggbbff>: Customize UI colors using RGBA hex.

  Example Usage:
    * `i3lock-color -c 1d2021 --indicator` — Lock the screen with a solid color and indicator.
    * `i3lock-color -i ~/Pictures/wallpaper.jpg -B 5 --time-color ffffffff` — Use a background image with blur and white time display.
    * `i3lock-color --nofork && systemctl suspend` — Lock the screen synchronously before suspending.
*/

{
  flake.nixosModules.apps."i3lock-color" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."i3lock-color" ];
    };
}

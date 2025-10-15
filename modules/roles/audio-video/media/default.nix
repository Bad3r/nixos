{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  getApp =
    rawHelpers.getApp or (
      name:
      if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
        lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
      else
        throw "Unknown NixOS app '${name}' (role audio-video.media)"
    );
  getApps = rawHelpers.getApps or (names: map getApp names);
  mediaApps = [
    "ffmpeg-full"
    "ffmpegthumbnailer"
    "gst-libav"
    "gst-plugins-good"
    "gst-plugins-bad"
    "gst-plugins-ugly"
  ];
  mediaImports = getApps mediaApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "audio-video.media" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = mediaImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles."audio-video".media = {
    metadata = {
      canonicalAppStreamId = "AudioVideo";
      categories = [ "AudioVideo" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}

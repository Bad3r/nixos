# The nixos-local marketplace's plugins (marketplace/) and the app each one
# runs: while a plugin is enabled in _plugins.nix, nixos.nix turns its app on
# and _marketplace.nix points the plugin's command option at the app.
{
  browser-webfetch = {
    app = "browser-fetch";
    option = "fetchCommand";
  };
  kagi-websearch = {
    app = "kagi-search";
    option = "searchCommand";
  };
}

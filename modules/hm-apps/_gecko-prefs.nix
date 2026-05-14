/*
  Internal: shared Gecko-browser preferences
  Description: user_pref values applied to every Firefox/Floorp/LibreWolf profile.

  Notes:
    * Reader-mode colors come from Stylix's own reader-mode wiring.
    * `fonts` is forwarded from `config.stylix.fonts`; pass `null` to let
      the browser use its built-in defaults.
    * Floorp workspaces stay in floorp.nix because they are Floorp-specific.
*/

{
  lib,
  fonts ? null,
}:
let
  geckoSearch = import ./_gecko-search.nix { };
in
{
  commonSettings =
    (lib.optionalAttrs (fonts != null) {
      "font.name.serif.x-western" = fonts.serif.name;
      "font.name.sans-serif.x-western" = fonts.sansSerif.name;
      "font.name.monospace.x-western" = fonts.monospace.name;
    })
    // geckoSearch.settings
    // {
      # about:config without the warning prompt.
      "browser.aboutConfig.showWarning" = false;

      # Allow userChrome.css / userContent.css to load.
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

      "browser.ctrlTab.sortByRecentlyUsed" = true;
      "browser.startup.page" = 3;
      "browser.tabs.closeWindowWithLastTab" = false;
      "browser.tabs.warnOnClose" = true;
      "browser.tabs.insertAfterCurrentExceptPinned" = true;
      "browser.tabs.splitview.hasUsed" = true;
      "browser.sessionstore.restore_pinned_tabs_on_demand" = true;

      # Do not check or prompt to become the system default browser.
      "browser.shell.checkDefaultBrowser" = false;
      "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true;

      # Keep Arabic out of automatic translation prompts.
      "browser.translations.neverTranslateLanguages" = "ar";

      # Pre-enable extensions delivered through the Nix scope (default 15 would
      # leave system-scope XPIs installed-but-disabled on first launch).
      "extensions.autoDisableScopes" = 0;
      "extensions.pictureinpicture.enable_picture_in_picture_overrides" = true;
      "extensions.webcompat.perform_injections" = true;

      # Caret browsing always-on; disable F7 shortcut so it is not toggled off
      # accidentally.
      "accessibility.browsewithcaret" = true;
      "accessibility.browsewithcaret_shortcut.enabled" = false;

      # Always prompt for the download location.
      "browser.download.useDownloadDir" = false;
      "browser.download.always_ask_before_handling_new_types" = true;
      # Force the print dialog to default to the built-in PDF backend on
      # every HM activation. Firefox writes the user's last selection back
      # to this pref, so leaving it declared intentionally clobbers any
      # other choice each rebuild.
      "print_printer" = "Mozilla Save to PDF";
      "print.more-settings.open" = true;

      # Route xdg-open / `firefox <url>` invocations to a new tab in the
      # current window (override.external=3). Also route target="_blank" links
      # and `window.open()` calls to a new tab instead of replacing the current
      # page or opening a separate window.
      "browser.link.open_newwindow" = 3;
      "browser.link.open_newwindow.override.external" = 3;
      # New tabs are brought to the foreground when opened.
      "browser.tabs.loadInBackground" = false;

      # Keep cookie / certificate management buttons enabled in preferences.
      "pref.privacy.disable_button.cookie_exceptions" = false;
      "pref.privacy.disable_button.view_cookies" = false;
      "security.disable_button.openCertManager" = false;

      # Disable the built-in password manager; Bitwarden / 1Password handle this.
      "signon.rememberSignons" = false;
      "signon.autofillForms" = false;
      "signon.generation.enabled" = false;
      "signon.management.page.breach-alerts.enabled" = false;
      # Disable Firefox form autofill (addresses/credit cards/heuristics).
      "extensions.formautofill.creditCards.enabled" = false;
      "extensions.formautofill.addresses.enabled" = false;
      "extensions.formautofill.heuristics.enabled" = false;
      "dom.forms.autocomplete.formautofill" = true;

      # Clear cookies+site data, form data, and history+downloads on every
      # shutdown. `privacy.sanitize.sanitizeOnShutdown` is the master switch:
      # without it the per-category `_v2` prefs below are inert because
      # Firefox short-circuits the shutdown sanitizer. The `_v2.*` namespace
      # is what modern Firefox (128+) reads; the legacy v1 keys are no-ops.
      "privacy.sanitize.sanitizeOnShutdown" = true;
      "privacy.clearOnShutdown_v2.cookiesAndStorage" = true;
      "privacy.clearOnShutdown_v2.formdata" = true;
      "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = false;

      # Open context menus on mouseup so a quick right-click-drag does not
      # dismiss the menu before it appears (X11 quirk).
      "ui.context_menus.after_mouseup" = true;

      # ui.systemUsesDarkTheme = 1 tells the browser the system is using
      # a dark theme, forcing chrome and prefers-color-scheme to dark.
      "ui.systemUsesDarkTheme" = 1;
      # layout.css.prefers-color-scheme.content-override:
      #   0 = dark, 1 = light, 2 = system, 3 = browser theme.
      "layout.css.prefers-color-scheme.content-override" = 0;

      # Vertical tabs sidebar. sidebar.revamp is required on Firefox 131+ for
      # sidebar.verticalTabs to actually apply.
      "sidebar.verticalTabs" = true;
      "sidebar.revamp" = true;
      "sidebar.open" = true;
      "sidebar.position_start" = true;
      "sidebar.command" = "viewTabsSidebar";
      "sidebar.verticalTabs.dragToPinPromo.dismissed" = true;

      # Show the bookmarks toolbar only on the new-tab page.
      "browser.toolbars.bookmarks.visibility" = "newtab";

      "reader.font_type" = "monospace";

      # VA-API hardware decoding under Wayland/X11.
      "media.ffmpeg.vaapi.enabled" = true;

      # Prefer xdg-desktop-portal for file picker and integration.
      "widget.use-xdg-desktop-portal.file-picker" = 1;
      "widget.use-xdg-desktop-portal" = 1;

      # Mute sponsored new-tab content.
      "browser.newtabpage.activity-stream.feeds.topsites" = true;
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;

      # Global Privacy Control header on all requests.
      "privacy.globalprivacycontrol.enabled" = true;

      # Reduce prefetching / speculative connections.
      "network.prefetch-next" = false;
      "network.dns.disablePrefetch" = true;
      "network.predictor.enabled" = false;
      "network.predictor.enable-prefetch" = false;
      "network.http.speculative-parallel-limit" = 0;
      "browser.urlbar.speculativeConnect.enabled" = false;

      # Disable Beacon API.
      "beacon.enabled" = false;
      # Strip known tracking parameters from URLs.
      "privacy.query_stripping.enabled" = true;

      # HTTPS-Only mode in normal and private windows.
      "dom.security.https_only_mode" = true;
      "dom.security.https_only_mode_pbm" = true;

      # FPI (privacy.firstparty.isolate) is deprecated; modern dFPI + network
      # partitioning replace it. Pin both explicitly.
      # See github.com/arkenfox/user.js/issues/1051
      "privacy.partition.network_state" = true;
      "network.cookie.cookieBehavior" = 5;
      "privacy.resistFingerprinting" = true;
      # Disabling timer jitter dodges a Claude AI infinite-loop freeze.
      # See codeberg.org/librewolf/issues/issues/1934
      "privacy.resistFingerprinting.reduceTimerPrecision.jitter" = false;
      "network.http.referer.XOriginTrimmingPolicy" = 2;

      # Cookie banner handling: attempt to auto-reject.
      "cookiebanners.service.mode" = 1;
      "cookiebanners.service.mode.privateBrowsing" = 1;
      "cookiebanners.ui.desktop.enabled" = true;

      # Keep Firefox Sync focused on extension/preferences state.
      "services.sync.engine.passwords" = false;
      "services.sync.engine.addresses" = false;
      "services.sync.engine.forms" = false;
      "services.sync.engine.creditcards" = false;
      "services.sync.engine.history" = false;
      "services.sync.engine.prefs" = true;

      # DevTools defaults.
      "devtools.everOpened" = true;
      "devtools.toolbox.host" = "window";
      "devtools.toolbox.splitconsole.open" = true;
      "devtools.webconsole.filter.netxhr" = true;

      # Keep Picture-in-Picture playback active when switching tabs.
      "media.videocontrols.picture-in-picture.enable-when-switching-tabs.enabled" = true;

      # Disable IPv6 address lookups.
      "network.dns.disableIPv6" = true;
    };
}

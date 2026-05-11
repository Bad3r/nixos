/*
  Internal: shared Gecko-browser preferences
  Description: user_pref values applied to every Firefox/Floorp/LibreWolf profile.

  Notes:
    * Reader-mode colors and font.name.* are intentionally absent. Stylix
      configures them via stylix.targets.{firefox,floorp,librewolf}.
    * WebRTC/DRM toggles stay in each browser module because they depend on
      per-browser HM options (enableWebRTC / enableDRM).
    * Floorp workspaces (floorp.workspaces.*) stay in floorp.nix because they
      are Floorp-specific.
*/

_: {
  commonSettings = {
    # about:config without the warning prompt.
    "browser.aboutConfig.showWarning" = false;

    # Allow userChrome.css / userContent.css to load.
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

    "browser.ctrlTab.sortByRecentlyUsed" = true;
    "browser.tabs.closeWindowWithLastTab" = false;

    # Pre-enable extensions delivered through the Nix scope (default 15 would
    # leave system-scope XPIs installed-but-disabled on first launch).
    "extensions.autoDisableScopes" = 0;

    # Caret browsing always-on; disable F7 shortcut so it is not toggled off
    # accidentally.
    "accessibility.browsewithcaret" = true;
    "accessibility.browsewithcaret_shortcut.enabled" = false;

    # Always prompt for the download location.
    "browser.download.useDownloadDir" = false;
    # Default the print dialog to the built-in PDF backend.
    "print_printer" = "Mozilla Save to PDF";

    # 1 = open links in the current tab/window. external=3 routes
    # xdg-open / `firefox <url>` invocations to a new tab in the current window.
    "browser.link.open_newwindow" = 1;
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

    # Clear offline data, form data, and history+downloads on every shutdown.
    "privacy.clearOnShutdown.offlineApps" = true;
    "privacy.clearOnShutdown_v2.formdata" = true;
    "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = true;

    # Open context menus on mouseup so a quick right-click-drag does not
    # dismiss the menu before it appears (X11 quirk).
    "ui.context_menus.after_mouseup" = true;

    # Hint sites to render in dark mode regardless of system color scheme.
    # ui.systemUsesDarkTheme forces prefers-color-scheme: dark; the override
    # value 0 means "force dark", 1 = light, 2 = system, 3 = browser theme.
    "ui.systemUsesDarkTheme" = 1;
    "layout.css.prefers-color-scheme.content-override" = 0;

    # Vertical tabs sidebar. sidebar.revamp is required on Firefox 131+ for
    # sidebar.verticalTabs to actually apply.
    "sidebar.verticalTabs" = true;
    "sidebar.revamp" = true;
    "sidebar.open" = true;
    "sidebar.position_start" = true;
    "sidebar.command" = "viewTabsSidebar";

    # Show the bookmarks toolbar only on the new-tab page.
    "browser.toolbars.bookmarks.visibility" = "newtab";

    # Reader-mode font. Reader colors come from Stylix.
    "reader.font_type" = "monospace";

    # VA-API hardware decoding under Wayland/X11.
    "media.ffmpeg.vaapi.enabled" = true;

    # Prefer xdg-desktop-portal for file picker and integration.
    "widget.use-xdg-desktop-portal.file-picker" = 1;
    "widget.use-xdg-desktop-portal" = 1;

    # Mute sponsored new-tab content.
    "browser.newtabpage.activity-stream.showSponsored" = false;
    "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
    "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;

    # Global Privacy Control header on all requests.
    "privacy.globalprivacycontrol.enabled" = true;

    # Disable Firefox Suggest (quicksuggest); keep engine suggestions working.
    "browser.urlbar.quicksuggest.enabled" = false;
    "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
    "browser.urlbar.suggest.quicksuggest.sponsored" = false;

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

    # Cookie banner handling: attempt to auto-reject.
    "cookiebanners.service.mode" = 1;
    "cookiebanners.service.mode.privateBrowsing" = 1;
    "cookiebanners.ui.desktop.enabled" = true;
  };
}

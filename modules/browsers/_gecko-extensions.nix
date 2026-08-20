/*
  Internal: shared Gecko-browser extensions
  Description: ExtensionSettings policy, and per-profile extension package lists,
*/

{
  config,
  lib,
  pkgs,
  # Whether the host enables programs.firefoxpwa.extended. Gates the firefoxpwa
  # management extension so it is only installed where the native connector and
  # CLI also exist (see firefox.nix/librewolf.nix).
  firefoxpwaEnabled ? false,
  firefoxpwaPackage ? null,
}:
let
  geckoExtensionData = import ./_gecko-extension-data.nix { inherit lib; };
  uboDynamicRules = import ./_ubo-dynamic-rules.nix { inherit lib; };
  inherit (uboDynamicRules)
    checkedHostnameSwitches
    checkedMediumModeRules
    ublockOriginHostnameSwitches
    ublockOriginMediumModeRules
    ;
  inherit (geckoExtensionData)
    toWidgetId
    ublockOrigin
    onePassword
    cookieAutoDelete
    darkreader
    foxyproxy
    languageTool
    printEdit
    raindrop
    savePage
    svgGobbler
    tabStash
    tridactyl
    violentmonkey
    webArchives
    firefoxpwaExt
    mkFirefoxpwaInstallUrl
    policyExtensionIds
    privateBrowsingExtensionIds
    mkNormalInstalledPolicy
    mkPrivateBrowsingPolicy
    ;

  stylixEnabled = config.stylix.enable or false;
  stylixPolarity = config.stylix.polarity or "auto";
  stylixColors = lib.attrByPath [ "lib" "stylix" "colors" ] { } config;
  stylixColorsWithHash = lib.attrByPath [ "withHashtag" ] { } stylixColors;
  colorWithHash = color: if builtins.substring 0 1 color == "#" then color else "#${color}";
  getStylixColor =
    name: fallback:
    if lib.hasAttr name stylixColorsWithHash then
      stylixColorsWithHash.${name}
    else if lib.hasAttr name stylixColors then
      colorWithHash stylixColors.${name}
    else
      fallback;
  ublockOriginUiTheme =
    if
      stylixEnabled
      && builtins.elem stylixPolarity [
        "dark"
        "light"
      ]
    then
      stylixPolarity
    else
      "auto";
  ublockOriginAccentColor = getStylixColor "base0D" "#aca0f7";

  # Browser-side trust manifest for the managed 1Password extension. The
  # 1Password GUI module owns the /run/wrappers/bin target.
  onePasswordNativeMessagingHost =
    pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/com.1password.1password.json"
      (
        builtins.toJSON {
          name = "com.1password.1password";
          description = "1Password BrowserSupport";
          path = "/run/wrappers/bin/1Password-BrowserSupport";
          type = "stdio";
          allowed_extensions = [ onePassword ];
        }
      );

  unifiedExtensionsArea = [
    (toWidgetId cookieAutoDelete)
    (toWidgetId darkreader)
    (toWidgetId webArchives)
    (toWidgetId languageTool)
    (toWidgetId violentmonkey)
    (toWidgetId svgGobbler)
    (toWidgetId printEdit)
    (toWidgetId savePage)
    (toWidgetId foxyproxy)
  ];

  navBarWidgets = [
    "back-button"
    "stop-reload-button"
    "forward-button"
    "customizableui-special-spring1"
    "customizableui-special-spring2"
    "firefox-view-button"
    "developer-button"
    (toWidgetId ublockOrigin)
    "urlbar-container"
    (toWidgetId raindrop)
    (toWidgetId onePassword)
    "unified-extensions-button"
    "customizableui-special-spring3"
    "customizableui-special-spring4"
    "vertical-spacer"
  ];

  toolbarPlacements = {
    "widget-overflow-fixed-list" = [ ];
    "unified-extensions-area" = unifiedExtensionsArea;
    "nav-bar" = navBarWidgets;
    "toolbar-menubar" = [ "menubar-items" ];
    TabsToolbar = [ ];
    "vertical-tabs" = [ "tabbrowser-tabs" ];
    PersonalToolbar = [ "personal-bookmarks" ];
  };

  toolbarSeen = unifiedExtensionsArea ++ [
    (toWidgetId onePassword)
    (toWidgetId raindrop)
    (toWidgetId ublockOrigin)
    "developer-button"
    "screenshot-button"
  ];

  toolbarState = {
    placements = toolbarPlacements;
    seen = toolbarSeen;
    dirtyAreaCache = [
      "unified-extensions-area"
      "nav-bar"
      "TabsToolbar"
      "vertical-tabs"
      "toolbar-menubar"
      "PersonalToolbar"
    ];
    currentVersion = 23;
    newElementCount = 4;
  };

  onePasswordToolbarIcon = ../stylix/icons/1password-outline.svg;
  userChrome = ''
    #${toWidgetId onePassword} > .toolbarbutton-icon,
    #${toWidgetId onePassword} > .toolbarbutton-badge-stack > .toolbarbutton-icon {
      list-style-image: url("file://${onePasswordToolbarIcon}") !important;
    }
  '';

  horizontalTabsBackup = toolbarState // {
    placements = toolbarPlacements // {
      TabsToolbar = [
        "tabbrowser-tabs"
        "new-tab-button"
      ];
      "vertical-tabs" = [ ];
    };
  };

  pageActionsPersistedActions = {
    ids = [
      "bookmark"
      "tab-stash_condordes_net"
      "_d07ccf11-c0cd-4938-a265-2a4d6ad01189_"
    ];
    idsInUrlbar = [
      "tab-stash_condordes_net"
      "_d07ccf11-c0cd-4938-a265-2a4d6ad01189_"
      "bookmark"
    ];
    idsInUrlbarPreProton = [ ];
    version = 1;
  };

  librewolfUblockOriginListData = builtins.fromJSON (
    builtins.readFile ./_librewolf-ubo-default-lists.json
  );
  # Filtered from LibreWolf upstream defaults:
  disabledLibrewolfLists = [
    "adguard-spyware-url"
    "ublock-badware"
    "urlhaus-1"
    "curben-phishing"
  ];
  librewolfUblockOriginLists = builtins.filter (
    list: !(builtins.elem list disabledLibrewolfLists)
  ) librewolfUblockOriginListData.lists;

  darkreaderBaseSettings = lib.importJSON ./_gecko-darkreader-settings.json;
  darkreaderStylixThemeColors = {
    darkSchemeBackgroundColor = getStylixColor "base00" "#282c34";
    darkSchemeTextColor = getStylixColor "base05" "#abb2bf";
    lightSchemeBackgroundColor = getStylixColor "base06" "#b6bdca";
    lightSchemeTextColor = getStylixColor "base00" "#282c34";
    scrollbarColor = getStylixColor "base00" "#282c34";
    selectionColor = getStylixColor "base0D" "#aca0f7";
  };
  withDarkreaderStylixColors = theme: theme // darkreaderStylixThemeColors;
  # Stylix owns colors only for the dynamicTheme engine; cssFilter/svgFilter
  # entries derive their output from the page, so the scheme colors are inert
  # there and would just be dead keys in storage.
  withStylixColorsIfDynamic =
    theme: if (theme.engine or null) == "dynamicTheme" then withDarkreaderStylixColors theme else theme;
  darkreaderSettings = darkreaderBaseSettings // {
    theme = withStylixColorsIfDynamic darkreaderBaseSettings.theme;
    customThemes = builtins.map (
      customTheme: customTheme // { theme = withStylixColorsIfDynamic customTheme.theme; }
    ) darkreaderBaseSettings.customThemes;
  };
  # Seed payload for Dark Reader. Written once as a writable file by
  # mkDarkreaderSeed (_gecko-mk-profile.nix) instead of through
  # extensions.settings, which force-rewrites storage.js on every activation
  # and would discard the user's runtime Dark Reader changes.
  darkreaderStorageSeed = pkgs.writeText "darkreader-storage.js" (
    lib.generators.toJSON { } darkreaderSettings
  );

  userscripts = builtins.fromJSON (builtins.readFile ./_gecko-userscripts.json);
  nixpkgsReviewGhaScript = userscripts."nixpkgs-review-gha";
  nixpkgsReviewGhaScriptId = toString nixpkgsReviewGhaScript.id;
  nixpkgsReviewGhaCode = builtins.readFile (./. + "/${nixpkgsReviewGhaScript.sourceFile}");
  nixpkgsReviewGhaRecord = {
    config = {
      enabled = 1;
      removed = 0;
      shouldUpdate = 0;
    };
    custom = {
      origInclude = true;
      origExclude = true;
      origMatch = true;
      origExcludeMatch = true;
      origTag = true;
      lastInstallURL = nixpkgsReviewGhaScript.installUrl;
      pathMap = { };
    };
    inherit (nixpkgsReviewGhaScript) meta;
    props = {
      position = nixpkgsReviewGhaScript.id;
      inherit (nixpkgsReviewGhaScript) uuid;
      lastModified = nixpkgsReviewGhaScript.updatedAt;
      lastUpdated = nixpkgsReviewGhaScript.updatedAt;
    };
  };

  extensionSettings =
    (lib.genAttrs policyExtensionIds mkNormalInstalledPolicy)
    # Whole-attrset override, not a nested `.private_browsing` assignment: `//`
    # is shallow, so the nested form would drop installation_mode/install_url
    # and leave these two add-ons uninstalled.
    // (lib.genAttrs privateBrowsingExtensionIds mkPrivateBrowsingPolicy)
    # The firefoxpwa management extension is only useful when the host enables
    # firefoxpwa: the native connector and `firefoxpwa` CLI are gated on the same
    # option, so an opt-out host gets no policy entry at all and cannot end up
    # with a policy-installed add-on stuck in a "connector not installed" state.
    # normal_installed still blocks uninstall here; it only adds Disable back.
    // lib.optionalAttrs firefoxpwaEnabled {
      "${firefoxpwaExt}" = {
        installation_mode = "normal_installed";
        install_url = mkFirefoxpwaInstallUrl (
          firefoxpwaPackage.version
            or (throw "firefoxpwaPackage.version is required when firefoxpwaEnabled is true")
        );
      };
    };

  primaryPackages = [ ];

  pentestingPackages = primaryPackages;

  workPackages = primaryPackages;
in
{
  extensionPolicies = {
    ExtensionSettings = extensionSettings;

    "3rdparty".Extensions."${ublockOrigin}" = {
      adminSettings = builtins.toJSON {
        assetsBootstrapLocation = librewolfUblockOriginListData.source;
      };
    };
  };

  inherit primaryPackages pentestingPackages workPackages;

  nativeMessagingHosts = [ onePasswordNativeMessagingHost ];

  sidebarSettings =
    let
      sidebarExtensionIds = [
        raindrop
        tabStash
        tridactyl
      ];
      sidebarTools = [
        raindrop
        tabStash
        "history"
      ];
    in
    {
      "sidebar.installed.extensions" = builtins.concatStringsSep "," sidebarExtensionIds;
      "sidebar.main.tools" = builtins.concatStringsSep "," sidebarTools;
    };

  toolbarSettings = {
    "browser.pageActions.persistedActions" = builtins.toJSON pageActionsPersistedActions;
    "browser.uiCustomization.horizontalTabsBackup" = builtins.toJSON horizontalTabsBackup;
    "browser.uiCustomization.navBarWhenVerticalTabs" = builtins.toJSON navBarWidgets;
    "browser.uiCustomization.state" = builtins.toJSON toolbarState;
  };

  inherit userChrome;
  inherit darkreaderStorageSeed;

  extensionStorage = {
    # uBO
    "${ublockOrigin}".settings = {
      advancedUserEnabled = true;
      cloudStorageEnabled = false;

      hiddenSettings = { };
      importedLists = [ ];

      showIconBadge = false;
      uiAccentCustom = stylixEnabled;
      uiAccentCustom0 = ublockOriginAccentColor;
      uiTheme = ublockOriginUiTheme;

      hostnameSwitchesString = builtins.concatStringsSep "\n" (
        checkedHostnameSwitches ublockOriginHostnameSwitches
      );

      dynamicFilteringString = builtins.concatStringsSep "\n" (
        checkedMediumModeRules ublockOriginMediumModeRules
      );

      netWhitelist = [
        "chrome-extension-scheme"
        "moz-extension-scheme"
      ];

      urlFilteringString = "";

      userFilters = ''
        ! https://octobox.io
        octobox.io##.btn-outline-light.btn-sm.btn

        ! https://web.webex.com
        web.webex.com##.cookie-banner-body

        ! https://www.google.com/sorry
        @@||www.google.com/sorry^$document
      '';

      selectedFilterLists = lib.unique (
        librewolfUblockOriginLists
        ++ [
          # Keep "My filters" enabled; uBO hides the element picker without it.
          "user-filters"

          # uBO Lists
          "ublock-filters"
          "ublock-privacy"
          "ublock-quick-fixes"
          "ublock-unbreak"

          # Ads Lists
          "easylist"
          "adguard-generic"

          # Privacy Lists
          "easyprivacy"
          "LegitimateURLShortener"
          "adguard-spyware-url" # AdGuard/uBO - URL Tracking Protection
          "block-lan"

          # Multipurpose
          "plowe-0"

          # Cookie notices
          "adguard-cookies"
          "ublock-cookies-adguard" # Fanboy - Anti-Facebook

          # Annoyances
          "adguard-other-annoyances"
          "adguard-popup-overlays"
          "adguard-widgets"
          "ublock-annoyances"

          # Additional regional lists
          "ara-0"
        ]
      );
    };

    # ViolentMonkey
    "${violentmonkey}".settings = {
      "code:${nixpkgsReviewGhaScriptId}" = nixpkgsReviewGhaCode;
      "scr:${nixpkgsReviewGhaScriptId}" = nixpkgsReviewGhaRecord;
    };

    # Dark Reader is intentionally absent here: extensions.settings force-writes
    # storage.js on every activation, discarding the user's runtime Dark Reader
    # changes. It is seeded once as a writable file instead; see
    # darkreaderStorageSeed above and mkDarkreaderSeed in _gecko-mk-profile.nix.

    # Tabliss is intentionally unmanaged: it is not in the extension policy set,
    # and the archived dotfiles export (tabliss/tabliss.json) is dropped rather
    # than ported. The managed new-tab surface stays Firefox's activity-stream,
    # configured in _gecko-prefs.nix.
  };
}

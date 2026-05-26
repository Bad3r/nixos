/*
  Internal: shared Gecko-browser extensions
  Description: ExtensionSettings policy, and per-profile extension package lists,
*/

{
  config,
  lib,
  pkgs,
}:
let
  # Use AMO's extension-ID URL form so the install URL matches the
  # ExtensionSettings policy key.
  amoLatestBaseUrl = "https://addons.mozilla.org/firefox/downloads/latest/";
  mkAmoInstallUrl =
    extension:
    "${amoLatestBaseUrl}${lib.replaceStrings [ "{" "}" ] [ "%7B" "%7D" ] extension}/latest.xpi";
  allowedWidgetChars = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789_-";
  toWidgetId =
    extension:
    let
      sanitizeChar = char: if builtins.elem char allowedWidgetChars then char else "_";
    in
    "${lib.stringAsChars sanitizeChar (lib.toLower extension)}-browser-action";

  ublockOrigin = "uBlock0@raymondhill.net";
  ublockOriginInstallUrl = mkAmoInstallUrl ublockOrigin;
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

  onePassword = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
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

  arabicDictionary = "ar@dictionaries.addons.mozilla.org";
  cookieAutoDelete = "CookieAutoDelete@kennydo.com";
  darkreader = "addon@darkreader.org";
  foxyproxy = "foxyproxy@eric.h.jung";
  languageTool = "languagetool-webextension@languagetool.org";
  printEdit = "printedit-we@DW-dev";
  raindrop = "jid0-adyhmvsP91nUO8pRv0Mn2VKeB84@jetpack";
  savePage = "savepage-we@DW-dev";
  svgGobbler = "{7962ff4a-5985-4cf2-9777-4bb642ad05b8}";
  tabStash = "tab-stash@condordes.net";
  tridactyl = "tridactyl.vim@cmcaine.co.uk";
  violentmonkey = "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}";
  wappalyzer = "wappalyzer@crunchlabz.com";
  webArchives = "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}";

  policyExtensionIds = [
    arabicDictionary
    cookieAutoDelete
    darkreader
    foxyproxy
    languageTool
    onePassword
    printEdit
    raindrop
    savePage
    svgGobbler
    tabStash
    tridactyl
    violentmonkey
    wappalyzer
    webArchives
  ];

  mkNormalInstalledPolicy = extension: {
    installation_mode = "normal_installed";
    install_url = mkAmoInstallUrl extension;
  };

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

  # uBO "medium mode": block third-party scripts and frames by default.
  # Commonly-used sites are pre-whitelisted; other sites need interactive
  # whitelisting via the uBO popup (per-site 3p-script/3p-frame => noop).
  # See https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "* * 3p-script block"
    "* * 3p-frame block"

    # Trusted sites: allow 3p scripts and frames.
    # Source-host match covers all subdomains.

    # Dev hosting & code collaboration
    "github.com * 3p-script noop"
    "github.com * 3p-frame noop"
    "github.dev * 3p-script noop"
    "github.dev * 3p-frame noop"
    "gitlab.com * 3p-script noop"
    "gitlab.com * 3p-frame noop"
    "bitbucket.org * 3p-script noop"
    "bitbucket.org * 3p-frame noop"
    "codeberg.org * 3p-script noop"
    "codeberg.org * 3p-frame noop"

    # Package registries & developer docs
    "hub.docker.com * 3p-script noop"
    "hub.docker.com * 3p-frame noop"
    "developer.mozilla.org * 3p-script noop"
    "developer.mozilla.org * 3p-frame noop"
    "developers.google.com * 3p-script noop"
    "developers.google.com * 3p-frame noop"
    "nixos.org * 3p-script noop"
    "nixos.org * 3p-frame noop"
    "formulae.brew.sh * 3p-script noop"
    "formulae.brew.sh * 3p-frame noop"

    # Q&A and knowledge
    "stackoverflow.com * 3p-script noop"
    "stackoverflow.com * 3p-frame noop"
    "stackexchange.com * 3p-script noop"
    "stackexchange.com * 3p-frame noop"
    "superuser.com * 3p-script noop"
    "superuser.com * 3p-frame noop"
    "askubuntu.com * 3p-script noop"
    "askubuntu.com * 3p-frame noop"
    "serverfault.com * 3p-script noop"
    "serverfault.com * 3p-frame noop"

    # Google productivity
    "docs.google.com * 3p-script noop"
    "docs.google.com * 3p-frame noop"
    "drive.google.com * 3p-script noop"
    "drive.google.com * 3p-frame noop"
    "mail.google.com * 3p-script noop"
    "mail.google.com * 3p-frame noop"
    "accounts.google.com * 3p-script noop"
    "accounts.google.com * 3p-frame noop"
    "myaccount.google.com * 3p-script noop"
    "myaccount.google.com * 3p-frame noop"

    # Microsoft 365
    "teams.cloud.microsoft * 3p-script noop"
    "teams.cloud.microsoft * 3p-frame noop"
    "login.microsoftonline.com * 3p-script noop"
    "login.microsoftonline.com * 3p-frame noop"
    "login.live.com * 3p-script noop"
    "login.live.com * 3p-frame noop"
    "login.microsoft.com * 3p-script noop"
    "login.microsoft.com * 3p-frame noop"

    # Cloud consoles
    "cloud.google.com * 3p-script noop"
    "cloud.google.com * 3p-frame noop"

    # AI tools
    "chatgpt.com * 3p-script noop"
    "chatgpt.com * 3p-frame noop"
    "auth.openai.com * 3p-script noop"
    "auth.openai.com * 3p-frame noop"
    "claude.ai * 3p-script noop"
    "claude.ai * 3p-frame noop"
    "gemini.google.com * 3p-script noop"
    "gemini.google.com * 3p-frame noop"
    "notebooklm.google.com * 3p-script noop"
    "notebooklm.google.com * 3p-frame noop"
    "codeassist.google * 3p-script noop"
    "codeassist.google * 3p-frame noop"
    "codeassist.google.com * 3p-script noop"
    "codeassist.google.com * 3p-frame noop"
    "aistudio.google.com * 3p-script noop"
    "aistudio.google.com * 3p-frame noop"

    # Proton web properties
    "proton.me * 3p-script noop"
    "proton.me * 3p-frame noop"

    # Mozilla / extensions
    "addons.mozilla.org * 3p-script noop"
    "addons.mozilla.org * 3p-frame noop"

    # Raindrop.io
    "app.raindrop.io * 3p-script noop"
    "app.raindrop.io * 3p-frame noop"
  ];

  extensionSettings = (lib.genAttrs policyExtensionIds mkNormalInstalledPolicy) // {
    "${ublockOrigin}" = {
      installation_mode = "force_installed";
      install_url = ublockOriginInstallUrl;
      private_browsing = true;
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

  # uBO
  extensionStorage."${ublockOrigin}".settings = {
    advancedUserEnabled = true;
    cloudStorageEnabled = false;

    hiddenSettings = { };
    importedLists = [ ];

    showIconBadge = false;
    uiAccentCustom = stylixEnabled;
    uiAccentCustom0 = ublockOriginAccentColor;
    uiTheme = ublockOriginUiTheme;

    hostnameSwitchesString = builtins.concatStringsSep "\n" [
      "no-csp-reports: * true"
      "no-large-media: behind-the-scene false"
    ];

    dynamicFilteringString = builtins.concatStringsSep "\n" ublockOriginMediumModeRules;

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
  extensionStorage."${violentmonkey}".settings = {
    "code:${nixpkgsReviewGhaScriptId}" = nixpkgsReviewGhaCode;
    "scr:${nixpkgsReviewGhaScriptId}" = nixpkgsReviewGhaRecord;
  };
}

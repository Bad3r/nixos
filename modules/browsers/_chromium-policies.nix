/*
  Internal: shared managed-policy payloads for Chromium-family browsers
  Description: Managed extensions and the default-search provider apply to
  Google Chrome and ungoogled Chromium; DNS-over-HTTPS also applies to Brave
  Origin. Imported via a relative path; the leading underscore keeps this file
  out of module auto-discovery.

  `StandardManagementPolicyProvider::MustRemainInstalled` covers
  INSTALLATION_RECOMMENDED (`normal_installed`) as well as INSTALLATION_FORCED,
  so chrome://extensions still refuses uninstall; the only permission
  `normal_installed` adds back is Disable. Gecko behaves the same way, see
  modules/browsers/_gecko-extension-data.nix.
*/
let
  # Secure mode has no system-resolver fallback; see _mullvad-doh-url.nix for
  # why the URL itself cannot revert to the documented dns. name.
  managedDnsOverHttps = {
    DnsOverHttpsMode = "secure";
    DnsOverHttpsTemplates = import ./_mullvad-doh-url.nix;
  };
in
{
  inherit managedDnsOverHttps;

  managedExtensionSettings = {
    # uBlock Origin Lite
    "ddkjiahejlhfcafbddmgiahcphecmpfh" = {
      installation_mode = "normal_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
    # 1Password - Password Manager
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
      installation_mode = "normal_installed";
      update_url = "https://clients2.google.com/service/update2/crx";
    };
  };

  managedDefaultSearchProvider = {
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "Kagi";
    DefaultSearchProviderKeyword = "kagi.com";
    DefaultSearchProviderSearchURL = "https://kagi.com/search?q={searchTerms}";
    DefaultSearchProviderSuggestURL = "https://kagi.com/api/autosuggest?q={searchTerms}";
    DefaultSearchProviderIconURL = "https://kagi.com/favicon-32x32.png";
    DefaultSearchProviderEncodings = [ "UTF-8" ];
  };
}

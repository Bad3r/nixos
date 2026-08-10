/*
  Internal: uBlock Origin dynamic-filtering rules and their syntax guard.

  Keep this helper independent from module config and packages so the browser
  profile and the flake-level evaluation check consume the same rule set.
*/
{ lib }:
let
  mediumModeRuleError =
    rule:
    let
      # uBO trims each line and splits on runs of intra-line whitespace before
      # validating it. Tabs separate fields; line breaks separate records.
      hasLineBreak = lib.hasInfix "\n" rule || lib.hasInfix "\r" rule;
      normalizedRule = lib.replaceStrings [ "\t" ] [ " " ] rule;
      parts = lib.filter (part: part != "") (lib.splitString " " normalizedRule);
      src = builtins.elemAt parts 0;
      des = builtins.elemAt parts 1;
      type = builtins.elemAt parts 2;
      action = builtins.elemAt parts 3;
      # Keep the seed in uBO's normalized ASCII hostname shape. The wildcard,
      # internal pseudo-host, and bracketed IPv6 forms are intentional.
      isHost =
        host:
        host == "*"
        || builtins.match "[[][0-9a-f:]+[]]" host != null
        || builtins.match "[0-9a-z_]([0-9a-z_.-]*[0-9a-z_])?" host != null;
    in
    if hasLineBreak then
      "contains a line break, which uBO reads as two separate rules"
    else if builtins.length parts != 4 then
      "expected 4 space-separated fields"
    else if
      !builtins.elem type [
        "*"
        "3p"
        "image"
        "inline-script"
        "1p-script"
        "3p-script"
        "3p-frame"
      ]
    then
      "unknown type ${type}"
    else if
      !builtins.elem action [
        "block"
        "allow"
        "noop"
      ]
    then
      "unknown action ${action}"
    else if !isHost src then
      "source ${src} is not a valid uBO hostname"
    else if !isHost des then
      "destination ${des} is not a valid uBO hostname"
    else if des != "*" && type != "*" then
      "destination ${des} is named, which uBO accepts only with type *, not ${type}"
    else
      null;

  checkedMediumModeRules =
    rules:
    let
      errors = lib.concatMap (
        rule: lib.optional (mediumModeRuleError rule != null) "${rule} (${mediumModeRuleError rule})"
      ) rules;
    in
    lib.throwIf (
      errors != [ ]
    ) "unusable uBO dynamic filtering rules: ${lib.concatStringsSep "; " errors}" rules;

  # uBO "medium mode": block third-party scripts and frames by default.
  # Commonly-used sites are pre-whitelisted; other sites need interactive
  # whitelisting via the uBO popup (per-site 3p-script/3p-frame => noop).
  # See https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "* * 3p-script block"
    "* * 3p-frame block"

    # Trusted destinations: allowed on every site. uBO evaluates a named
    # destination before the blanket 3p-script/3p-frame rows above, and
    # `validateRuleParts` discards a named destination paired with anything
    # narrower than type `*`, so each entry covers script and frame together
    # and matches on hostname alone, never a request path.

    # Cloudflare Turnstile: /turnstile/v0/api.js plus the widget iframe.
    "* challenges.cloudflare.com * noop"

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
in
{
  inherit
    mediumModeRuleError
    checkedMediumModeRules
    ublockOriginMediumModeRules
    ;
}

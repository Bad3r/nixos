# uBlock Origin hostname switches and dynamic-filtering rules.
{ lib }:
let
  # Third-party CAPTCHA scripts and frames, allowed on every site.
  trustedDestinations = [
    # Cloudflare Turnstile
    "challenges.cloudflare.com"
    # Google reCAPTCHA
    "www.google.com"
    "www.gstatic.com"
    "recaptcha.google.com"
    "www.recaptcha.net"
  ];

  # Sites allowed to load third-party scripts and frames.
  trustedSites = [
    # Dev hosting & code collaboration
    "github.com"
    "github.dev"
    "gitlab.com"
    "bitbucket.org"
    "codeberg.org"

    # Package registries & developer docs
    "hub.docker.com"
    "developer.mozilla.org"
    "developers.google.com"
    "nixos.org"
    "formulae.brew.sh"

    # Q&A and knowledge
    "stackoverflow.com"
    "stackexchange.com"
    "superuser.com"
    "askubuntu.com"
    "serverfault.com"

    # Google productivity
    "docs.google.com"
    "drive.google.com"
    "mail.google.com"
    "accounts.google.com"
    "myaccount.google.com"

    # Microsoft 365
    "teams.cloud.microsoft"
    "login.microsoftonline.com"
    "login.live.com"
    "login.microsoft.com"

    # Atlassian/Jira
    "atlassian.com"

    # Cloud consoles
    "cloud.google.com"

    # AI tools
    "chatgpt.com"
    "auth.openai.com"
    "claude.ai"
    "gemini.google.com"
    "notebooklm.google.com"
    "codeassist.google"
    "codeassist.google.com"
    "aistudio.google.com"

    # Proton web properties
    "proton.me"

    # Mozilla / extensions
    "addons.mozilla.org"

    # Raindrop.io
    "app.raindrop.io"
  ];
in
{
  ublockOriginHostnameSwitches = [
    "no-csp-reports: * true"
    "no-large-media: behind-the-scene false"
  ];

  # uBO "medium mode": block third-party scripts and frames by default.
  # See https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "* * 3p-script block"
    "* * 3p-frame block"
  ]
  # uBO accepts a named destination only with type *.
  ++ map (host: "* ${host} * noop") trustedDestinations
  ++ lib.concatMap (host: [
    "${host} * 3p-script noop"
    "${host} * 3p-frame noop"
  ]) trustedSites;
}

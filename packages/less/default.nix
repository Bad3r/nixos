{
  autoreconfHook,
  fetchurl,
  groff,
  lib,
  ncurses,
  perl,
  pcre2,
  stdenv,
  versionCheckHook,
  # Boolean options
  withSecure ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "less";
  version = "693";

  # v693 is a development tag and is currently consumed from GitHub.
  src = fetchurl {
    url = "https://github.com/gwsw/less/archive/refs/tags/v${finalAttrs.version}.tar.gz";
    hash = "sha256-gqJf71Ra3kdfpZEb2pScpNyl6b1MuAlpugt7+8Aiu/E=";
  };

  buildInputs = [
    ncurses
    pcre2
  ];

  nativeBuildInputs = [
    autoreconfHook
    groff
    perl
  ];

  preConfigure = ''
    substituteInPlace mkhelp.pl \
      --replace-fail '#! /usr/bin/env perl' '#!${perl}/bin/perl'

    # GitHub source archives are equivalent to a git checkout; generate
    # release artifacts as recommended by upstream before configure.
    make -f Makefile.aut distfiles
  '';

  outputs = [
    "out"
    "man"
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    (lib.withFeatureAs true "regex" "pcre2")
    (lib.withFeature withSecure "secure")
  ];

  strictDeps = true;

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  doInstallCheck = true;

  meta = {
    homepage = "https://www.greenwoodsoftware.com/less/";
    description = "More advanced file pager than 'more'";
    changelog = "https://raw.githubusercontent.com/gwsw/less/v${finalAttrs.version}/NEWS";
    license = lib.licenses.gpl3Plus;
    mainProgram = "less";
    maintainers = with lib.maintainers; [
      mdaniels5757
      yiyu
    ];
    platforms = lib.platforms.unix;
  };
})

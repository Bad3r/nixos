{
  lib,
  writeShellApplication,
  pinentry-qt,
  pinentry-curses,
}:

writeShellApplication {
  name = "pinentry-dispatch";

  meta = {
    description = "Session-aware pinentry wrapper that falls back to curses outside graphical sessions";
    homepage = "https://gnupg.org/software/pinentry/index.html";
    license = lib.licenses.gpl2Plus;
    mainProgram = "pinentry-dispatch";
    platforms = lib.platforms.linux;
  };

  runtimeInputs = [
    pinentry-qt
    pinentry-curses
  ];

  text = /* bash */ ''
    if [[ -n "''${WAYLAND_DISPLAY:-}" || -n "''${DISPLAY:-}" ]]; then
      exec ${lib.getExe pinentry-qt} "$@"
    fi

    exec ${lib.getExe pinentry-curses} "$@"
  '';
}

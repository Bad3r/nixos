{
  lib,
  writeShellApplication,
  libsecret,
  libnotify,
}:

writeShellApplication {
  name = "winapps-askpass";

  meta = {
    description = "FreeRDP askpass helper that reads the WinApps RDP password from the Secret Service";
    homepage = "https://github.com/winapps-org/winapps";
    license = lib.licenses.mit;
    mainProgram = "winapps-askpass";
    platforms = lib.platforms.linux;
  };

  runtimeInputs = [
    libsecret
    libnotify
  ];

  # FreeRDP runs `$FREERDP_ASKPASS '<prompt>'` through popen and reads the first stdout line;
  # on a non-zero exit or empty output it falls back to a terminal prompt, which reads EOF in
  # a menu launch. The WinApps launcher discards FreeRDP's output, hence the notification.
  # The attributes match the `secret-tool store` line in docs/winapps/operations.md.
  text = /* bash */ ''
    fail() {
      echo "winapps-askpass: $1" >&2
      if ! notify-send --app-name=WinApps --icon=dialog-error --urgency=critical "WinApps" "$1"; then
        echo "winapps-askpass: notify-send failed" >&2
      fi
      exit 1
    }

    secret="$(secret-tool lookup service winapps account rdp)" \
      || fail "RDP password unavailable: the keyring is locked or holds no item with service=winapps account=rdp."
    [ -n "$secret" ] || fail "The keyring returned an empty RDP password."
    printf '%s\n' "$secret"
  '';
}

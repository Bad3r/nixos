_: {
  configurations.nixos.tpnix.module = {
    # Prefer Arabic-capable Noto faces ahead of MonoLisa for Arabic text.
    host.fontconfig.extraRules = ''
      <match target="pattern">
        <test name="lang" compare="contains">
          <string>ar</string>
        </test>
        <edit name="family" mode="prepend" binding="strong">
          <string>Noto Sans Arabic UI</string>
          <string>Noto Sans Arabic</string>
          <string>Noto Naskh Arabic</string>
          <string>DejaVu Sans Mono</string>
        </edit>
      </match>
    '';
  };
}

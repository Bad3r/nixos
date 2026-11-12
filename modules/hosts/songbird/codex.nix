_: {
  configurations.nixos.songbird.module = {
    programs.codex.extended = {
      codeMode.enable = true;
      voice.enable = true;
    };
  };
}

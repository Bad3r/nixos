{
  #services.pulseaudio.enable = false;
  security.rtkit.enable = true; # Real‑time scheduling for PipeWire threads

  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
    wireplumber.enable = true;
  };
}

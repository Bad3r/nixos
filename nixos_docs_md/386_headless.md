## Headless

Common configuration for headless machines (e.g., Amazon EC2 instances).

Disables [vesa](options.html#opt-boot.vesa), serial consoles, [emergency mode](options.html#opt-systemd.enableEmergencyMode), [grub splash images](options.html#opt-boot.loader.grub.splashImage) and configures the kernel to reboot automatically on panic.

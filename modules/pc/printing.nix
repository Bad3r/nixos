# Module: pc/printing.nix
# Purpose: Printing configuration
# Namespace: flake.modules.nixos.pc
# Pattern: Personal computer configuration - Extends base for desktop systems

# modules/printing-cups.nix

{
  flake.modules.nixos.pc.services.printing.enable = false;
}

## Emacs

**Table of Contents**

[Installing Emacs](#module-services-emacs-installing)

[Running Emacs as a Service](#module-services-emacs-running)

[Configuring Emacs](#module-services-emacs-configuring)

[Emacs](https://www.gnu.org/software/emacs/) is an extensible, customizable, self-documenting real-time display editor — and more. At its core is an interpreter for Emacs Lisp, a dialect of the Lisp programming language with extensions to support text editing.

Emacs runs within a graphical desktop environment using the X Window System, but works equally well on a text terminal. Under macOS, a “Mac port” edition is available, which uses Apple’s native GUI frameworks.

Nixpkgs provides a superior environment for running Emacs. It’s simple to create custom builds by overriding the default packages. Chaotic collections of Emacs Lisp code and extensions can be brought under control using declarative package management. NixOS even provides a **systemd** user service for automatically starting the Emacs daemon.

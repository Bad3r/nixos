## Customizing display configuration

**Table of Contents**

[Forcing display modes](#module-hardware-display-modes)

[Crafting custom EDID files](#module-hardware-display-edid-custom)

[Assigning EDID files to displays](#module-hardware-display-edid-assign)

[Pulling files from linuxhw/EDID database](#module-hardware-display-edid-linuxhw)

[Using XFree86 Modeline definitions](#module-hardware-display-edid-modelines)

[Complete example for Asus PG278Q](#module-hardware-display-pg278q)

This section describes how to customize display configuration using:

- kernel modes

- EDID files

Example situations it can help you with:

- display controllers (external hardware) not advertising EDID at all,

- misbehaving graphics drivers,

- loading custom display configuration before the Display Manager is running,

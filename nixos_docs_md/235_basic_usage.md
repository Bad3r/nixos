## Basic Usage

A minimal configuration looks like this:

```programlisting
{ services.samba.enable = true; }
```

This configuration automatically enables `smbd`, `nmbd` and `winbindd` services by default.

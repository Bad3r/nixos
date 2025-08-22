## Custom additions

Sometimes third-party or custom scripts such as a modified theme may be needed. `oh-my-zsh` provides the [`ZSH_CUSTOM`](https://github.com/robbyrussell/oh-my-zsh/wiki/Customization#overriding-internals) environment variable for this which points to a directory with additional scripts.

The module can do this as well:

```programlisting
{ programs.zsh.ohMyZsh.custom = "~/path/to/custom/scripts"; }
```

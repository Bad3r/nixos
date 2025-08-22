## Re-attaching to WeeChat

WeeChat runs in a screen session owned by a dedicated user. To explicitly allow your another user to attach to this session, the `screenrc` needs to be tweaked by adding [multiuser](https://www.gnu.org/software/screen/manual/html_node/Multiuser.html#Multiuser) support:

```programlisting
{
  programs.screen.screenrc = ''
    multiuser on
    acladd normal_user
  '';
}
```

Now, the session can be re-attached like this:

```programlisting
screen -x weechat/weechat-screen
```

_The session name can be changed using [services.weechat.sessionName.](options.html#opt-services.weechat.sessionName)_

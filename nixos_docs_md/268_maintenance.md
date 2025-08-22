## Maintenance

### Backups

Backups can be configured with the options in [services.gitlab.backup](options.html#opt-services.gitlab.backup.keepTime). Use the [services.gitlab.backup.startAt](options.html#opt-services.gitlab.backup.startAt) option to configure regular backups.

To run a manual backup, start the `gitlab-backup` service:

```programlisting
$ systemctl start gitlab-backup.service
```

### Rake tasks

You can run GitLab’s rake tasks with `gitlab-rake` which will be available on the system when GitLab is enabled. You will have to run the command as the user that you configured to run GitLab with.

A list of all available rake tasks can be obtained by running:

```programlisting
$ sudo -u git -H gitlab-rake -T
```

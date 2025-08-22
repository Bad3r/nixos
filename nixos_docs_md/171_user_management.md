## User management

After the Akkoma service is running, the administration utility can be used to [manage users](https://docs.akkoma.dev/stable/administration/CLI_tasks/user/). In particular an administrative user can be created with

```programlisting
$ pleroma_ctl user new <nickname> <email> --admin --moderator --password <password>
```

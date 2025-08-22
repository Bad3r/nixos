## Creating the admin user

After Pleroma service is running, all [Pleroma administration utilities](https://docs-develop.pleroma.social/) can be used. In particular an admin user can be created with

```programlisting
$ pleroma_ctl user new <nickname> <email>  --admin --moderator --password <password>
```

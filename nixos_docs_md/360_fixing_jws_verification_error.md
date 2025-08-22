## Fixing JWS Verification error

It is possible that your account credentials file may become corrupt and need to be regenerated. In this scenario lego will produce the error `JWS verification error`. The solution is to simply delete the associated accounts file and re-run the affected service(s).

```programlisting

# Find the accounts folder for the certificate

systemctl cat acme-example.com.service | grep -Po 'accounts/[^:]*'
export accountdir="$(!!)"

# Move this folder to some place else

mv /var/lib/acme/.lego/$accountdir{,.bak}

# Recreate the folder using systemd-tmpfiles

systemd-tmpfiles --create

# Get a new account and reissue certificates

# Note: Do this for all certs that share the same account email address

systemctl start acme-example.com.service
```

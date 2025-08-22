## Regenerating certificates

Should you need to regenerate a particular certificate in a hurry, such as when a vulnerability is found in Let’s Encrypt, there is now a convenient mechanism for doing so. Running `systemctl clean --what=state acme-example.com.service` will remove all certificate files and the account data for the given domain, allowing you to then `systemctl start acme-example.com.service` to generate fresh ones.

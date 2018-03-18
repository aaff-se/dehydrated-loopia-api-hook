# Dehydrated Loopia API hook

A DNS challenge hook for automatic renewal of Letsencrypt wildcard certificates through the Loopia API

### Requirements
Apart from Dehydrated, its only dependencies are bash, libxml2 and curl.  
The script assumes that you have a Loopia API user with rights to get, add and remove zone records, with the credentials to user in the loopia-api-user.auth file.  
Before the first run you need to manually add a txt record to _acme-challenge.DOMAIN.COM (you can't update a record that doesn't exist)
  
### Limitations
The script assumes that you only request certificates for DOMAIN.COM and *.DOMAIN.COM - not SUB.DOMAIN.COM or *.SUB.DOMAIN.COM

### Additional notes

I keep this hook in [Dehydrated-folder]/hooks/loopia/  
If you don't, you'll need to adjust the auth file source link accordingly.

This is built upon a script by Joakim Reinert  
https://gist.github.com/jreinert/49aca3b5f3bf2c5d73d8

### ToDo
make use of hook chain to do all the dns updates together, and then wait 5 mins to check, rather than waiting 5 mins between each update.

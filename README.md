# devca.sh

Because your hair is too precious to pull it all out trying to ignore SSL check...

Devca.sh is a Minimalist script to setup &amp; manage local certificate authority and issue locally trusted certificates for development purposes 

## Example: Secure local Github Entreprise Server TLS connection

I assume you run your GHES on `192.168.52.184`, repalce by your ip

I assume you registered your public ssh key in the config GUI `https://192.168.52.184:8443`

**copy CA to your GHES appliance**

```
scp -P 122 ~/.devca/ca.crt  admin@192.168.52.184:/home/admin
```

**connect to the instance**

```
$ ssh -p 122 admin@192.168.52.184
     ___ _ _   _  _      _      ___     _                    _
    / __(_) |_| || |_  _| |__  | __|_ _| |_ ___ _ _ _ __ _ _(_)___ ___
   | (_ | |  _| __ | || | '_ \ | _|| ' \  _/ -_) '_| '_ \ '_| (_-</ -_)
    \___|_|\__|_||_|\_,_|_.__/ |___|_||_\__\___|_| | .__/_| |_/__/\___|
                                                   |_|

Administrative shell access is permitted for troubleshooting and performing
documented operations procedures only. Modifying system and application files,
running programs, or installing unsupported software packages may void your
support contract. Please contact GitHub support at https://support.github.com
if you have a question about the activities allowed by your support contract.

INFO: Release version: 3.15.1
INFO: 4 CPUs, 31GB RAM on VMWare
INFO: License: evaluation; Seats: unlimited; Will expire in 45 days.
INFO: Load average: 2.02 2.71 3.03
INFO: Usage for mounted root partition: 36G of 196G (20%)
INFO: Usage for mounted user data partition: 23G of 196G (13%)
INFO: TLS: enabled; Certificate will expire in 364 days.
INFO: Stand-Alone Instance
INFO: Configuration run in progress: false
==============================
       Upgrade Notice         
   Version: 3.15              

Minimum Recommended System Requirements for versions 3.15 and later:
  - Root Disk: 400 GB        
  - Data Disk: 500 GB        
```

**install the CA**

```
admin@192-168-52-184:~$ ghe-ssl-ca-certificate-install -c ca.crt 
 --> Installing CA certificate to /usr/local/share/ca-certificates/LocalRootCA_7D199401C0D1532951AAC722B39B452CF8460535.crt...
 --> Updating CA certificates...
 --> Done.
```


**apply GHES config**

```
admin@192-168-52-184:~$ ghe-config-apply
2025-01-22T01:27:36+0000 Preparing storage device...
2025-01-22T01:27:39+0000 Updating configuration...
2025-01-22T01:27:39+0000 Reloading system services...
2025-01-22T01:28:15+0000 Running migrations...
2025-01-22T01:30:55+0000 Reloading application services...
2025-01-22T01:32:12+0000 Validating services...
2025-01-22T01:32:31+0000 Done!
admin@192-168-52-184:~$ 

```


**update system-wide cert bundles**

```
sudo update-ca-certificates --verbose --fresh
```

**exit guest & go back to host**

**update hosts file**

sudo nano /etc/hosts to add github.dev

```
192.168.52.184  github.dev
```

**create new certificate signed by local ca**

```
./devca.sh newtls github.dev
```

**Go back to the interarface and upload a certificate**

https://192.168.52.184:8443/setup/settings

1/ find fost name section, update it:

```
github.dev
```

2/ Find TLS section, update it

Certificate (*.pem)
=> upload ~/.devca/certs/github.dev.crt

Unencrypted key (*.key) 
=> upload ~/.devca/private/github.dev.key

3/ cick on [save settings]

wait for reconfigure to finish


**check in browser, connection is secure**

![github dev - secure](https://github.com/user-attachments/assets/8b493936-0cbe-4718-ac77-585d1c6df71d)






## Example: Generate JKS for bitbucket local server

I assume you did run `devca.sh install-ca` and have your CA installed globally

I assume you have a bitbucket server (`atlassian/bitbucket`) running locally, in a docker container `cb0bded71316`:

```
$ docker ps | grep bitbucket
cb0bded71316   atlassian/bitbucket                                             "/usr/bin/tini -- /e…"   2 months ago   Up 5 minutes           0.0.0.0:7990->7990/tcp, :::7990->7990/tcp, 0.0.0.0:7999->7999/tcp, :::7999->7999/tcp, 0.0.0.0:7991->8443/tcp, :::7991->8443/tcp   bitbucket

```

I assume that you correctly setup `/var/atlassian/application-data/bitbucket/shared/bitbucket.properties` file within the container:

```
server.additional-connector.1.port=8443
server.additional-connector.1.ssl.enabled=true
server.additional-connector.1.ssl.key-store=/var/atlassian/application-data/bitbucket/shared/bitbucket.jks
server.additional-connector.1.ssl.key-store-password=admin1234
server.additional-connector.1.ssl.key-password=admin1234
```

Generate new JKS, copy it into `/var/atlassian/application-data/bitbucket/shared/bitbucket.jks`, restart container

```
./devca.sh newjks tomcat bitbucket.jks admin1234 localhost
docker cp bitbucket.jks cb0bded71316:/var/atlassian/application-data/bitbucket/shared/bitbucket.jks
docker restart cb0bded71316
```

`docker logs -f cb0bded71316` Logs should show a happy restart

Now try to `curl -v https://localhost:7991`, you should see only happy things

```
16:39 $ curl -v https://localhost:7991
*   Trying 127.0.0.1:7991...
* Connected to localhost (127.0.0.1) port 7991 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.0 (OUT), TLS header, Certificate Status (22):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS header, Certificate Status (22):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS header, Finished (20):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.2 (OUT), TLS header, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server did not agree to a protocol
* Server certificate:
*  subject: CN=localhost
*  start date: Jan 18 12:25:29 2025 GMT
*  expire date: Apr 23 12:25:29 2027 GMT
*  subjectAltName: host "localhost" matched cert's "localhost"
*  issuer: CN=LocalRootCA
*  SSL certificate verify ok.
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
> GET / HTTP/1.1
> Host: localhost:7991
> User-Agent: curl/7.81.0
> Accept: */*
> 
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* Mark bundle as not supporting multiuse
< HTTP/1.1 302 
< X-AREQUESTID: @SMHTOXx759x64x0
< x-xss-protection: 1; mode=block
< x-frame-options: SAMEORIGIN
< x-content-type-options: nosniff
< Pragma: no-cache
< Expires: Thu, 01 Jan 1970 00:00:00 GMT
< Cache-Control: no-cache
< Cache-Control: no-store
< Location: https://localhost:7991/dashboard
< Content-Language: en-US
< Content-Length: 0
< Date: Sat, 18 Jan 2025 12:39:15 GMT
< 
* Connection #0 to host localhost left intact

```

Going back for the entire reason for this example to exist: gitlab's evaluate client.

Now you can use it properly, without modification like this:

```
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
evaluate-bitbucket -s https://localhost:7991 -t YOUR_BITBUCKET_ACCESS_TOKEN
```

![image](https://github.com/user-attachments/assets/9e4a9021-57c2-462b-bf15-98130b672696)




# Import CA in chrome

- goto `chrome://settings/certificates?search=certificate`
- click on import
- select `/usr/local/share/ca-certificates/devrootca.crt`
- tick "...trust websites..."
- ok


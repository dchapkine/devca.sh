# devca.sh

Because your hair is too precious to pull it all out trying to ignore SSL check...

Devca.sh is a Minimalist script to setup &amp; manage local certificate authority and issue locally trusted certificates for development purposes 

# Example: Generate JKS for bitbucket local server

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


# Import CA in chrome

- goto `chrome://settings/certificates?search=certificate`
- click on import
- select `/usr/local/share/ca-certificates/devrootca.crt`
- tick "...trust websites..."
- ok


# uyuni-cert-creator
This script is intended to create new server certificates for the uyuni-server and uyuni-db based on SUMA 4.3.x CA certificate. 

Current State: WORK IN PROGRESS needs some addition test 

Usage:
On the SUSE Manager Server 4.3 run: 
uyuni-cert-creator (FQDN name of the Common Name) 

And if alternative names (SANs) are required e.g. for the uyuni-db container:
uyuni-cert-creator (FQDN name of the Common Name) "reportdb,db"


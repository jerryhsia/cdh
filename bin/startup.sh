#!/bin/bash

service krb5kdc start
service kadmin start
service ntpd start

/usr/bin/docker-quickstart
/home/cloudera/cloudera-manager --force --express

tail -f /dev/null
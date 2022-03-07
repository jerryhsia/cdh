#!/bin/bash

set -e

cd /tmp

cp /tmp/startup.sh /root/

yum_install() {
    mv /etc/yum.repos.d /etc/yum.repos.d.bak
    mkdir /etc/yum.repos.d/ && cp *.repo /etc/yum.repos.d/
    yum makecache
    yum install -y vim wget lsof strace
    yum clean all
}

install_kdc() {
    yum -y install krb5-libs krb5-server krb5-workstation

    cp -f krb5.conf /etc/krb5.conf
    cp -f kadm5.acl /var/kerberos/krb5kdc/kadm5.acl
    cp -f kdc.conf /var/kerberos/krb5kdc/kdc.conf
    mkdir /etc/krb5.conf.d/
    mkdir /root/keytab

    expect -c "
    spawn /usr/sbin/kdb5_util create -s -r HADOOP.COM
    expect {
            \"Enter KDC database master key\" {send \"hadoop\r\"; exp_continue}
            \"Re-enter KDC database master key to verify:\" {send \"hadoop\r\"}
    }
    expect interact"

    for user in hbase hdfs hive hue impala oozie solr spark sqoop2 yarn zookeeper
    do
        expect -c "
        spawn kadmin.local -q \"add_principal ${user}/user\"
        expect {
                \"Enter password\" {send \"${user}\r\"; exp_continue}
                \"Re-enter password\" {send \"${user}\r\"}
        }
        expect interact"

        kadmin.local -q "xst -k /root/keytab/${user}_user.keytab ${user}/user@HADOOP.COM"
    done

    for user in root
    do
        expect -c "
        spawn kadmin.local -q \"add_principal ${user}/admin\"
        expect {
                \"Enter password\" {send \"${user}\r\"; exp_continue}
                \"Re-enter password\" {send \"${user}\r\"}
        }
        expect interact"
    done

    chmod +r /root/keytab/*
    sleep 5
}

yum_install
install_kdc
#!/bin/bash

set -e

cd /tmp
cp /tmp/startup.sh /root/

yum_install() {
    mv /etc/yum.repos.d /etc/yum.repos.d.bak
    mkdir /etc/yum.repos.d/ && cp *.repo /etc/yum.repos.d/
    yum makecache
    yum install -y wget lsof strace
}

upgrade_java() {
    wget -O jdk-8u151-linux-x64.tar.gz https://repo.huaweicloud.com/java/jdk/8u151-b12/jdk-8u151-linux-x64.tar.gz
    tar -xf jdk-8u151-linux-x64.tar.gz 
    rm -rf /usr/java/jdk1.7.0_67-cloudera
    mv jdk1.8.0_151 /usr/java/jdk1.7.0_67-cloudera
    rm -rf jdk*
}

upgrade_hive() {
    wget -O apache-hive-1.2.2-bin.tar.gz https://archive.apache.org/dist/hive/hive-1.2.2/apache-hive-1.2.2-bin.tar.gz
    
    tar -xf apache-hive-1.2.2-bin.tar.gz
    cp -r apache-hive-1.2.2-bin/lib /usr/lib/hive/lib120
    rm -rf /usr/lib/hive/bin/hive && mv hive /usr/lib/hive/bin/

    /etc/init.d/mysqld start
    mysql -uroot -pcloudera metastore -e "source apache-hive-1.2.2-bin/scripts/metastore/upgrade/mysql/upgrade-1.1.0-to-1.2.0.mysql.sql"
    echo "upgrade result:$?"
    rm -rf apache-hive-*
}

upgrade_hbase_thrift2() {
    rm -rf /usr/lib64/cmf/service/hbase/hbase.sh
    mv hbase.sh /usr/lib64/cmf/service/hbase/
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

        kadmin.local -q "xst -k /root/keytab/${user}_admin.keytab ${user}/admin@HADOOP.COM"
    done
    sleep 5
}

# yum_install
# install_kdc

upgrade_hive
upgrade_java
upgrade_hbase_thrift2
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
    wget -O apache-hive-2.1.0-bin.tar.gz https://ai-platform-package.gz.bcebos.com/bigdata/apache-hive-2.1.0-bin.tar.gz
    
    tar -xf apache-hive-2.1.0-bin.tar.gz
    mv apache-hive-2.1.0-bin apache-hive-bin
    cp -r apache-hive-bin/lib /usr/lib/hive/libnew
    mv /usr/lib/hive/libnew/hive-service-rpc-2.1.0.jar /usr/lib/hive/libnew/hive-service-rpc-2.1.0.jar.bak
    rm -rf /usr/lib/hive/bin/hive && mv hive /usr/lib/hive/bin/

    cd apache-hive-bin/scripts/metastore/upgrade/mysql/

    /etc/init.d/mysqld start
    mysql -uroot -pcloudera metastore -e "source upgrade-1.1.0-to-1.2.0.mysql.sql"
    mysql -uroot -pcloudera metastore -e "source upgrade-1.2.0-to-2.0.0.mysql.sql"
    mysql -uroot -pcloudera metastore -e "source upgrade-2.0.0-to-2.1.0.mysql.sql"
    echo "upgrade result:$?"

    cd /tmp
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
    chmod +x /root/keytab/*
    sleep 5
}

# yum_install
# install_kdc

upgrade_hive
upgrade_java
upgrade_hbase_thrift2
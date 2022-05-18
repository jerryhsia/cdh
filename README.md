# docker-cdh

基于 [https://hub.docker.com/r/cloudera/quickstart](https://hub.docker.com/r/cloudera/quickstart) 构建，并做了以下升级：

- 内置安装krb5kdc
	- 基础镜像中生成了大数据组件客户端的keytab文件，位于`/root/keytab`，可直接复制使用。
	- 可以直接开启kerberos认证，管理员账号：`root/admin@HADOOP.COM` 密码：`root`
- Java7升级Java8
- Hive升级、见分支管理
- HBaseThrift升级Thrift2

# 分支管理

| 分支 | 镜像 | 内容 |
|  ----  | ----  | ----  |
| v0 | jerry9916/cdh:v0 | Java8、Hive1.1.0 |
| v1 | jerry9916/cdh:v1 | Java8、Hive1.2.0 |
| v2 | jerry9916/cdh:v2 | Java8、Hive2.1.1 |

# principal

| principal | 密码 | keytab |
|  ----  | ----  | ----  |
| root/admin@HADOOP.COM | root | /root/keytab/root_admin.keytab |
| hbase/user@HADOOP.COM | hbase | /root/keytab/hbase_user.keytab |
| hdfs/user@HADOOP.COM | hdfs | /root/keytab/hdfs_user.keytab |
| hive/user@HADOOP.COM | hive | /root/keytab/hive_user.keytab |
| hue/user@HADOOP.COM | hue | /root/keytab/hue_user.keytab |
| impala/user@HADOOP.COM | impala | /root/keytab/impala_user.keytab |
| oozie/user@HADOOP.COM | oozie | /root/keytab/oozie_user.keytab |
| solr/user@HADOOP.COM | solr | /root/keytab/solr_user.keytab |
| spark/user@HADOOP.COM | spark | /root/keytab/spark_user.keytab |
| sqoop2/user@HADOOP.COM | sqoop2 | /root/keytab/sqoop2_user.keytab |
| yarn/user@HADOOP.COM | yarn | /root/keytab/yarn_user.keytab |
| zookeeper/user@HADOOP.COM | zookeeper | /root/keytab/zookeeper_user.keytab |
| hbase@HADOOP.COM | hbase | /root/keytab/hbase.keytab |
| hdfs@HADOOP.COM | hdfs | /root/keytab/hdfs.keytab |
| hive@HADOOP.COM | hive | /root/keytab/hive.keytab |
| hue@HADOOP.COM | hue | /root/keytab/hue.keytab |
| impala@HADOOP.COM | impala | /root/keytab/impala.keytab |
| oozie@HADOOP.COM | oozie | /root/keytab/oozie.keytab |
| solr@HADOOP.COM | solr | /root/keytab/solr.keytab |
| spark@HADOOP.COM | spark | /root/keytab/spark.keytab |
| sqoop2@HADOOP.COM | sqoop2 | /root/keytab/sqoop2.keytab |
| yarn@HADOOP.COM | yarn | /root/keytab/yarn.keytab |
| zookeeper@HADOOP.COM | zookeeper | /root/keytab/zookeeper.keytab |

# 快速使用

```bash
docker stop cdh
docker rm cdh

docker run -d --name cdh --hostname=quickstart.cloudera --privileged=true \
-v /root/jerry:/root/jerry \
-v /etc/localtime:/etc/localtime \
-p 8722:8020 \
-p 8701:8022 \
-p 8702:7180 \
-p 8703:21050 \
-p 8704:50070 \
-p 8705:50075 \
-p 8706:50010 \
-p 8721:50020 \
-p 8708:8890 \
-p 8725:60000 \
-p 8709:60010 \
-p 8726:60020 \
-p 8727:60030 \
-p 8710:10002 \
-p 8711:25010 \
-p 8712:25020 \
-p 8713:18088 \
-p 8714:8088 \
-p 8715:19888 \
-p 8716:7187 \
-p 8717:11000 \
-p 8718:8888 \
-p 8719:10000 \
-p 8720:9090 \
-p 8723:88 \
-p 8724:2181 \
jerry9916/cdh:v0 \
/bin/bash -c '/root/startup.sh'
```

启动后进入管理页开启服务：

- 管理页地址：http://宿主机IP:8702
- 帐号：cloudera
- 密码：cloudera

# 端口映射

```bash
8722:8020  # hdfs
8701:8022
8702:7180  # cloudera manager
8703:21050 # impala
8704:50070
8705:50075
8706:50010
8721:50020
8708:8890
8725:60000 # hbase master
8709:60010 # hbase master info
8726:60020 # hbase regionserver
8727:60030 # hbase regionserver info
8710:10002
8711:25010
8712:25020
8713:18088
8714:8088
8715:19888
8716:7187
8717:11000
8718:8888
8719:10000 # hive server2
8720:9090  # hbase thrift
8723:88    # kerberos kdc
8724:2181  # zookeeper
```

# 其他问题

1、当cloudera manager中monitor不响应时，执行以下命令：

```bash
python2.6 /usr/lib64/cmf/agent/build/env/bin/cmf-agent --package_dir /usr/lib64/cmf/service --agent_dir /var/run/cloudera-scm-agent --lib_dir /var/lib/cloudera-scm-agent --logfile /var/log/cloudera-scm-agent/cloudera-scm-agent.log --daemon --comm_name cmf-agent --pidfile /var/run/cloudera-scm-agent/cloudera-scm-agent.pid --hostname=quickstart.cloudera --host_id=quickstart.cloudera
```

2、HBase开启Kerberos时，请在cloudera manager配置管理中增加以下配置。

**HBase服务**

`hbase-site.xml 的 HBase 服务高级配置代码段（安全阀）`修改为：

```xml
<property>
	<name>hbase.thrift.security.qop</name>
	<value>auth</value>
</property>
```

**HDFS服务**

`core-site.xml 的群集范围高级配置代码段（安全阀）`修改为：

```xml
<property>
  	<name>hadoop.proxyuser.hbase.hosts</name>
  	<value>*</value>
</property>
<property>
  	<name>hadoop.proxyuser.hbase.groups</name>
  	<value>*</value>
</property>
```

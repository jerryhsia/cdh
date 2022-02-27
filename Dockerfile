FROM iregistry.baidu-int.com/xiajie01/cloudera-quickstart:latest
WORKDIR /root

COPY bin/* conf/* /tmp/
RUN /tmp/install.sh

CMD ["/root/startup.sh"]
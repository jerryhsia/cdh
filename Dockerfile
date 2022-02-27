FROM docker.mirrors.ustc.edu.cn/cloudera/quickstart:latest
WORKDIR /root

COPY bin/* conf/* /tmp/
RUN /tmp/install.sh

CMD ["/root/startup.sh"]
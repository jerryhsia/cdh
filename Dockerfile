FROM jerry9916/docker-cdh:base
WORKDIR /root

COPY bin/* conf/* /tmp/

RUN /tmp/install.sh

CMD ["/root/startup.sh"]
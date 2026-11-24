FROM ubuntu:26.04

COPY prepare-base.sh /tmp/prepare-base.sh
RUN bash -e /tmp/prepare-base.sh && rm /tmp/prepare-base.sh

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

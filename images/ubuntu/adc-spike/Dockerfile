FROM ubuntu:26.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        jq \
        libicu-dev \
        libssl-dev \
        lsb-release \
        sudo \
        systemd \
        systemd-sysv \
    && printf '%s\n' 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90assumeyes \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]

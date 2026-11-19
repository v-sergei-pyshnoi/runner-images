ARG BASE_IMAGE=ubuntu:26.04
FROM ${BASE_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        jq \
        libdigest-sha-perl \
        libicu-dev \
        libssl-dev \
        lsb-release \
        man-db \
        sudo \
        systemd \
        systemd-sysv \
        wget \
    && shasum --version \
    && printf '%s\n' 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90assumeyes \
    && install -d -m 0700 /opt/packer-provisioning \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]

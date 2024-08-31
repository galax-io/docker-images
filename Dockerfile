FROM ubuntu:22.04 as fat

LABEL maintainer="Galaxio Team"
LABEL authors="i.akhaltsev"

# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TZ='UTC'

# Proxy Envs
ARG https_proxy
ARG http_proxy
ARG HTTPS_PROXY
ARG HTTP_PROXY
ARG no_proxy="localhost,127.0.0.1,.local,docker"
ARG NO_PROXY="localhost,127.0.0.1,.local,docker"

SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]

# Update apt-get && Install packages
RUN export DEBIAN_FRONTEND=noninteractive  \
    && apt-get upgrade -y && apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates locales tzdata \
    curl wget jq \
    unzip \
    gnupg2 adduser netcat-openbsd git-all \
    && sed -i "/${LANG}/s/^# //g" /etc/locale.gen && locale-gen  \
    && rm -rf /var/lib/apt/lists/*

# distroless build
FROM gcr.io/distroless/base-debian12:latest-amd64

COPY --from=fat /etc/passwd /etc/group /etc/
COPY --from=fat /etc/ssl /etc/ssl
COPY --from=fat /etc/ld.so.conf.d/ /etc/ld.so.conf.d/
COPY --from=fat /usr/local/bin /usr/local/bin
COPY --from=fat /usr/bin/mawk /usr/bin/awk
COPY --from=fat /usr/bin/dash /bin/sh
COPY --from=fat /bin/bash /bin/bash
COPY --from=fat /bin/nc.openbsd /bin/
COPY --from=fat /usr/bin/cp /usr/bin/base64 /usr/bin/basename /usr/bin/cat /usr/bin/chmod /usr/bin/chown bin/chgrp /usr/bin/dd /usr/bin/curl /usr/bin/printf /usr/bin/sleep /usr/bin/cut \
/usr/bin/date /usr/bin/dirname /usr/bin/du /usr/bin/echo /usr/bin/env /usr/bin/find /usr/bin/expr \
/usr/bin/git /usr/bin/grep /usr/bin/gzip /usr/bin/jq /usr/bin/ln /usr/bin/ls /usr/bin/mkdir /usr/bin/mv /usr/bin/openssl /usr/bin/printenv \
/usr/bin/ps /usr/bin/readlink /usr/bin/rm /usr/bin/sed /usr/bin/sleep /usr/bin/sort /usr/bin/tar /usr/bin/touch \
/usr/bin/tr /usr/bin/true /usr/bin/uname /usr/bin/unzip /usr/bin/xargs /usr/bin/mkfifo /usr/bin/timeout \
/usr/bin/tail /usr/bin/tee /usr/bin/nc /usr/bin/nc.openbsd /usr/bin/
COPY --from=fat /etc/alternatives/nc /etc/alternatives/
COPY --from=fat /usr/lib/git-core /usr/lib/git-core
COPY --from=fat /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive
COPY --from=fat /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
COPY --from=fat /usr/libexec /usr/libexec

# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' TZ='UTC'
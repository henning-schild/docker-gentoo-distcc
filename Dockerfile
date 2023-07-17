FROM ksmanis/stage3:20230717@sha256:30d3428ea909f944d40de0cb2407d399b8a3d1b4a1f8b6213cd86b18436204f4 AS distcc-builder
RUN set -eux; \
    printf '[gentoo]\nsync-type = webrsync\n' > /etc/portage/repos.conf; \
    emerge --sync; \
    emerge --info; \
    emerge --quiet-build -tv distcc; \
    rm -rf /var/cache/distfiles/ /var/db/repos/gentoo/; \
    distcc --version

FROM distcc-builder AS distcc-tcp
ARG TARGETPLATFORM
# renovate: datasource=github-tags depName=krallin/tini
ARG TINI_VERSION=0.19.0
ARG TINI_GPGKEY=595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7
RUN set -eux; \
    case "$TARGETPLATFORM" in \
        "linux/386") TINI_ARCH="i386" ;; \
        "linux/amd64") TINI_ARCH="amd64" ;; \
        "linux/arm/v6" | "linux/arm/v7") TINI_ARCH="armhf" ;; \
        "linux/arm64") TINI_ARCH="arm64" ;; \
        "linux/ppc64le") TINI_ARCH="ppc64le" ;; \
        *) echo "Error: Unsupported TARGETPLATFORM '$TARGETPLATFORM'" >&2; exit 1 ;; \
    esac; \
    curl -fL "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-${TINI_ARCH}" -o /usr/local/bin/tini; \
    curl -fL "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-${TINI_ARCH}.asc" -o /usr/local/bin/tini.asc; \
    curl -fL "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-${TINI_ARCH}.sha256sum" -o /usr/local/bin/tini.sha256sum; \
    GNUPGHOME="$(mktemp -d)"; \
    export GNUPGHOME; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${TINI_GPGKEY}"; \
    gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
    gpgconf --kill all; \
    sed -i "s#tini-${TINI_ARCH}#/usr/local/bin/tini#" /usr/local/bin/tini.sha256sum; \
    sha256sum --check --strict /usr/local/bin/tini.sha256sum; \
    rm -rf "${GNUPGHOME}" /usr/local/bin/tini.asc /usr/local/bin/tini.sha256sum; \
    chmod +x /usr/local/bin/tini; \
    tini --version
COPY docker-entrypoint-tcp.sh /usr/local/bin/docker-entrypoint.sh
# distccd exits with code 143 for SIGTERM; remap it to 0
ENTRYPOINT ["tini", "-e", "143", "--", "docker-entrypoint.sh"]
EXPOSE 3632
HEALTHCHECK CMD ["lsdistcc", "-pgcc", "localhost"]

FROM distcc-builder AS distcc-ssh
ENV SSH_USERNAME=distcc-ssh
COPY docker-entrypoint-ssh.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 22
HEALTHCHECK CMD </dev/tcp/localhost/22 || exit 1

FROM distcc-builder AS distcc-tcp-test
ARG TEST_USERNAME=notroot
RUN useradd ${TEST_USERNAME}
WORKDIR /home/${TEST_USERNAME}/
USER ${TEST_USERNAME}
COPY --chown=${TEST_USERNAME} tests/test.c ./
COPY --chown=${TEST_USERNAME} tests/test.sh ./
ENV DISTCC_BACKOFF_PERIOD=0
ENV DISTCC_FALLBACK=0
ENV DISTCC_VERBOSE=1
CMD ["./test.sh"]

FROM distcc-tcp-test AS distcc-ssh-test
ARG TEST_USERNAME=notroot
COPY --chown=${TEST_USERNAME} --chmod=600 tests/ssh_config .ssh/config
COPY --chown=${TEST_USERNAME} --chmod=600 tests/ssh_ed25519_key .ssh/id_ed25519

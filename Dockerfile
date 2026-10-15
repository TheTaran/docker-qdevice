FROM debian:bookworm-slim AS builder

ARG QDEVICE_REPOSITORY=https://github.com/corosync/corosync-qdevice.git
ARG QDEVICE_REF=v3.0.4

RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        autoconf automake build-essential ca-certificates git \
        libcmap-dev libcorosync-common-dev libnss3-dev \
        libtool libvotequorum-dev pkg-config; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN set -eux; \
    git init; \
    git remote add origin "${QDEVICE_REPOSITORY}"; \
    git fetch --depth 1 origin "${QDEVICE_REF}"; \
    git checkout --detach FETCH_HEAD; \
    case "${QDEVICE_REF}" in v[0-9]*) git tag --force "${QDEVICE_REF}" HEAD ;; esac; \
    printf '%s\n' "${QDEVICE_REF#v}" > .tarball-version; \
    git rev-parse HEAD > /build-revision

RUN set -eux; \
    ./autogen.sh; \
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
        --disable-qdevices --disable-systemd --enable-secure-build; \
    make -j"$(nproc)"; \
    make DESTDIR=/output install; \
    install -Dm0644 /build-revision /output/usr/share/doc/corosync-qdevice/SOURCE_COMMIT

FROM debian:bookworm-slim

ARG QDEVICE_REPOSITORY=https://github.com/corosync/corosync-qdevice.git
ARG QDEVICE_REF=v3.0.4
ARG QNETD_UID=903
ARG QNETD_GID=903

LABEL org.opencontainers.image.title="Corosync QNetd" \
      org.opencontainers.image.description="Corosync QDevice network daemon built from upstream source" \
      org.opencontainers.image.source="${QDEVICE_REPOSITORY}" \
      org.opencontainers.image.version="${QDEVICE_REF}"

RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        adduser ca-certificates libnspr4 libnss3 libnss3-tools openssh-server procps tini util-linux; \
    rm -rf /var/lib/apt/lists/*; \
    addgroup --system --gid "${QNETD_GID}" coroqnetd; \
    adduser --system --uid "${QNETD_UID}" --gid "${QNETD_GID}" \
        --home /etc/corosync/qnetd --no-create-home coroqnetd; \
    install -d -o coroqnetd -g coroqnetd -m 0750 /etc/corosync/qnetd /run/corosync-qnetd

COPY --from=builder /output/usr/ /usr/

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY sshd_config.qnetd /etc/ssh/sshd_config.qnetd

USER coroqnetd:coroqnetd

VOLUME ["/etc/corosync/qnetd"]
EXPOSE 5403/tcp 2222/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["corosync-qnetd-tool", "-s"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD []

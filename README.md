# docker-qdevice

Container image for the Corosync QDevice network daemon (`corosync-qnetd`), built directly from the official [corosync/corosync-qdevice](https://github.com/corosync/corosync-qdevice) source repository.

## Overview

QNetd runs outside a Corosync cluster and provides an independent quorum vote. It is particularly useful for two-node and other even-sized clusters.

This project provides:

- a reproducible multi-stage source build
- automatic NSS certificate initialization on first start
- persistent certificate and CA storage
- an unprivileged runtime user
- a read-only container filesystem with all Linux capabilities dropped
- a built-in health check
- local and production Compose templates
- tag-driven GitHub Container Registry releases
- automated upstream-version monitoring

The image intentionally contains no SSH server. Proxmox VE installations must use the manual QDevice certificate workflow described below instead of `pvecm qdevice setup`.

## Project Versions

There are two independent versions:

| Version | Meaning |
| --- | --- |
| Project release, for example `v1.0.0` | Version of this container project and its deployment behavior |
| `QDEVICE_REF`, currently `v3.0.4` | Corosync QDevice source tag or commit compiled into the image |

The resolved upstream commit is stored in the image at `/usr/share/doc/corosync-qdevice/SOURCE_COMMIT`.

## Quick Start

Create local configuration from the templates:

```sh
cp .env.example .env
cp compose-template.yml compose.yaml
docker compose up -d --build
docker compose ps
```

The QNetd service listens on TCP port `5403` by default.

## Production Deployment

Use a released GHCR image rather than building on the production host:

```sh
cp .env.example .env
cp compose-production-template.yml compose.yaml
```

Set `QDEVICE_IMAGE` in `.env` to the required immutable release tag, then start it:

```sh
docker compose pull
docker compose up -d
```

Do not use `latest` when a deployment must remain pinned to a known release.

## Certificate Enrollment

On first start, the container creates its NSS database and QNetd CA under `/etc/corosync/qnetd/nssdb` in the persistent volume.

Copy the CA certificate out:

```sh
docker compose cp \
  qnetd:/etc/corosync/qnetd/nssdb/qnetd-cacert.crt \
  ./qnetd-cacert.crt
```

Then perform the manual enrollment:

1. Import the CA on one cluster node:

   ```sh
   corosync-qdevice-net-certutil -i -c qnetd-cacert.crt
   ```

2. Generate a certificate request. The cluster name must exactly match `totem.cluster_name` in `corosync.conf`:

   ```sh
   corosync-qdevice-net-certutil -r -n CLUSTER_NAME
   ```

3. Copy `qdevice-net-node.crq` into the container's persistent `nssdb` directory.

4. Sign the request:

   ```sh
   docker compose exec qnetd corosync-qnetd-certutil \
     -s -c /etc/corosync/qnetd/nssdb/qdevice-net-node.crq \
     -n CLUSTER_NAME
   ```

5. Copy `cluster-CLUSTER_NAME.crt` back to the node and import it with `corosync-qdevice-net-certutil -M`.

6. Distribute the generated PKCS#12 client certificate to the remaining cluster nodes according to the upstream Corosync QDevice documentation.

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `QDEVICE_REF` | `v3.0.4` | Upstream source tag, branch, or commit used by local builds |
| `QNETD_UID` | `903` | Runtime user ID used at image build time |
| `QNETD_GID` | `903` | Runtime group ID used at image build time |
| `QNETD_PORT` | `5403` | Published host TCP port |
| `QDEVICE_IMAGE` | `ghcr.io/thetaran/docker-qdevice:latest` | Image used by the production template |

Container arguments are passed directly to `corosync-qnetd`; foreground mode (`-f`) is always enabled:

```yaml
services:
  qnetd:
    command: ["-s", "required"]
```

Use the image itself to display the options supported by the compiled release:

```sh
docker run --rm ghcr.io/thetaran/docker-qdevice:latest \
  corosync-qnetd -h
```

## Persistent Data and Backup

The `qnetd-data` volume contains the QNetd CA, private keys, signed cluster certificates, and NSS database. Back it up securely.

- Losing it requires re-enrolling all QDevice clients.
- Exposing it compromises trust for every enrolled cluster.
- Normal upgrades must retain the volume.
- Never include its contents in Git or container images.

## Development

```sh
sh tests/test-entrypoint.sh
docker compose -f compose-template.yml config --quiet
docker build -t docker-qdevice:development .
```

For a complete runtime check:

```sh
cp compose-template.yml compose.yaml
docker compose up -d --build
docker compose ps
docker compose logs qnetd
```

## Releases

Project releases use tags with a `v` prefix, such as `v1.0.0`. Each release requires a matching file:

```text
.github/release-notes/v1.0.0.md
```

The release workflow publishes:

- `ghcr.io/thetaran/docker-qdevice:<full-version>`
- `ghcr.io/thetaran/docker-qdevice:<major.minor>` for three-part versions
- `ghcr.io/thetaran/docker-qdevice:latest` for designated two-part master releases
- `ghcr.io/thetaran/docker-qdevice:sha-<commit>`

Releases, tags, and images are created only after explicit approval.

## Upstream and License

Corosync QDevice is developed by the [Corosync project](https://github.com/corosync/corosync-qdevice) and is distributed under its upstream license. The corresponding upstream license is included in the built image under `/usr/share/doc/corosync-qdevice/LICENSE`.

This repository is a container packaging project and is not affiliated with or endorsed by the Corosync project or Red Hat.

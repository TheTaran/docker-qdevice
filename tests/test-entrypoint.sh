#!/bin/sh
set -eu

script=docker-entrypoint.sh

test -x "${script}"
grep -q '^set -eu$' "${script}"
grep -q 'corosync-qnetd-certutil -i' "${script}"
grep -q 'exec corosync-qnetd -f' "${script}"
grep -q 'QNETD_SSH_ENABLED' "${script}"
grep -q 'QNETD_SSH_PASSWORD' "${script}"
grep -q 'QNetd Proxmox SSH setup mode is ENABLED' "${script}"
grep -q 'setpriv --reuid=903' "${script}"
grep -q 'https://github.com/corosync/corosync-qdevice.git' Dockerfile
grep -q 'COPY --from=builder' Dockerfile
grep -q '^USER coroqnetd:coroqnetd$' Dockerfile
if grep -Eq 'apt-get install.*corosync-qnetd|^[[:space:]]+corosync-qnetd[[:space:]\\]*$' Dockerfile; then
    echo "Dockerfile must compile QNetd instead of installing its binary package" >&2
    exit 1
fi

source_ref="$(sed -n 's/^ARG QDEVICE_REF=//p' Dockerfile | head -1)"
test -n "${source_ref}"
grep -q "^QDEVICE_REF=${source_ref}$" .env.example
grep -q "QDEVICE_REF:-${source_ref}" compose-template.yml

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${script}"
fi

echo "Entrypoint checks passed"

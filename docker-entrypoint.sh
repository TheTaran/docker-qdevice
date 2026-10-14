#!/bin/sh
set -eu

data_dir=/etc/corosync/qnetd
db_dir="${data_dir}/nssdb"
runtime_dir=/run/corosync-qnetd

if [ "${1:-}" = "corosync-qnetd" ]; then
    shift
fi

if [ "${1:-}" != "" ] && [ "${1#-}" = "$1" ]; then
    exec "$@"
fi

if ! setpriv --reuid=903 --regid=903 --clear-groups test -w "${data_dir}"; then
    echo "error: ${data_dir} is not writable by uid 903" >&2
    echo "Set the volume owner to uid/gid 903 or build with QNETD_UID/QNETD_GID." >&2
    exit 1
fi

if [ ! -d "${runtime_dir}" ]; then
    install -d -m 0750 "${runtime_dir}"
    chown 903:903 "${runtime_dir}"
fi

setpriv --reuid=903 --regid=903 --clear-groups /bin/sh -ceu '
    if [ ! -f "$1/cert9.db" ] && [ ! -f "$1/cert8.db" ]; then
        if [ -e "$1" ] && [ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
            echo "error: $1 is non-empty but has no recognizable certificate database" >&2
            exit 1
        fi
        echo "Initializing QNetd certificate database..."
        corosync-qnetd-certutil -i
    fi
' sh "${db_dir}"

if [ "${QNETD_SSH_ENABLED:-false}" = "true" ]; then
    : "${QNETD_SSH_PASSWORD:?Set QNETD_SSH_PASSWORD for the temporary Proxmox root login}"
    if [ ! -w /etc/shadow ]; then
        echo "error: SSH setup mode requires QNETD_READ_ONLY=false" >&2
        exit 1
    fi

    printf 'root:%s\n' "${QNETD_SSH_PASSWORD}" | chpasswd
    unset QNETD_SSH_PASSWORD

    install -d -m 0755 /run/sshd
    ssh-keygen -q -t ed25519 -N '' -f "${runtime_dir}/ssh_host_ed25519_key"
    /usr/sbin/sshd -f /etc/ssh/sshd_config.qnetd

    ssh_host="${QNETD_SSH_HOST:-NAS_IP}"
    ssh_port="${QNETD_SSH_PORT:-2222}"
    cat >&2 <<EOF

QNetd Proxmox SSH setup mode is ENABLED.

On the Proxmox node that will run the setup, add this to /root/.ssh/config:
Host ${ssh_host}
    User root
    Port ${ssh_port}
    StrictHostKeyChecking accept-new

Then run:
  pvecm qdevice setup ${ssh_host}

Proxmox will ask for the temporary root password configured as
QNETD_SSH_PASSWORD. The pvecm command always uses the root account.

After pvecm status shows the Qdevice flag, set QNETD_SSH_ENABLED=false,
set QNETD_READ_ONLY=true, remove QNETD_SSH_PASSWORD, and redeploy this container.
EOF
fi

exec setpriv --reuid=903 --regid=903 --clear-groups corosync-qnetd -f "$@"

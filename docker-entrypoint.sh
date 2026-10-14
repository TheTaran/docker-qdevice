#!/bin/sh
set -eu

data_dir=/etc/corosync/qnetd
db_dir="${data_dir}/nssdb"

if [ "${1:-}" = "corosync-qnetd" ]; then
    shift
fi

if [ "${1:-}" != "" ] && [ "${1#-}" = "$1" ]; then
    exec "$@"
fi

if [ ! -w "${data_dir}" ]; then
    echo "error: ${data_dir} is not writable by uid $(id -u)" >&2
    echo "Set the volume owner to uid/gid 903 or build with QNETD_UID/QNETD_GID." >&2
    exit 1
fi

if [ ! -f "${db_dir}/cert9.db" ] && [ ! -f "${db_dir}/cert8.db" ]; then
    if [ -e "${db_dir}" ] && [ -n "$(find "${db_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        echo "error: ${db_dir} is non-empty but has no recognizable certificate database" >&2
        exit 1
    fi
    echo "Initializing QNetd certificate database..."
    corosync-qnetd-certutil -i
fi

exec corosync-qnetd -f "$@"

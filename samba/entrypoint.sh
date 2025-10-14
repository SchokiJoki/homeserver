#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date --iso-8601=seconds)] $*"
}

SAMBA_USER=${SAMBA_USER:-backup}
SAMBA_PASSWORD=${SAMBA_PASSWORD:-}
SAMBA_WORKGROUP=${SAMBA_WORKGROUP:-WORKGROUP}
SAMBA_NETBIOS_NAME=${SAMBA_NETBIOS_NAME:-HOMESERVER}
SAMBA_SHARE_NAME=${SAMBA_SHARE_NAME:-backup}
SAMBA_SHARE_PATH=${SAMBA_SHARE_PATH:-/share/backup}
PUID=${PUID:-1000}
PGID=${PGID:-1000}
SAMBA_GROUP=${SAMBA_GROUP:-sambashare}

if [[ -z ${SAMBA_PASSWORD} ]]; then
  echo "SAMBA_PASSWORD environment variable must be set" >&2
  exit 1
fi

umask 0002
mkdir -p /var/log/samba
mkdir -p "$(dirname "${SAMBA_SHARE_PATH}")"
mkdir -p "${SAMBA_SHARE_PATH}"

existing_group_by_name=$(getent group "${SAMBA_GROUP}" || true)
existing_group_by_gid=$(getent group "${PGID}" || true)
if [[ -n ${existing_group_by_name} ]]; then
  if ! groupmod -o -g "${PGID}" "${SAMBA_GROUP}" 2>/dev/null; then
    SAMBA_GROUP=${existing_group_by_name%%:*}
  fi
elif [[ -n ${existing_group_by_gid} ]]; then
  SAMBA_GROUP=${existing_group_by_gid%%:*}
else
  if ! groupadd -g "${PGID}" "${SAMBA_GROUP}" 2>/dev/null; then
    SAMBA_GROUP=sambashare
    groupadd "${SAMBA_GROUP}" 2>/dev/null || true
  fi
fi

if id "${SAMBA_USER}" &>/dev/null; then
  usermod -g "${SAMBA_GROUP}" "${SAMBA_USER}" 2>/dev/null || true
  usermod -u "${PUID}" "${SAMBA_USER}" 2>/dev/null || true
else
  if getent passwd "${PUID}" >/dev/null; then
    SAMBA_USER=$(getent passwd "${PUID}" | cut -d: -f1)
  else
    useradd -M -s /usr/sbin/nologin -u "${PUID}" -g "${SAMBA_GROUP}" "${SAMBA_USER}" || \
      useradd -M -s /usr/sbin/nologin -g "${SAMBA_GROUP}" "${SAMBA_USER}"
  fi
fi

usermod -g "${SAMBA_GROUP}" "${SAMBA_USER}" 2>/dev/null || true

echo "${SAMBA_USER}:${SAMBA_PASSWORD}" | chpasswd 2>/dev/null || true
if pdbedit -L | grep -q "^${SAMBA_USER}:"; then
  log "Updating Samba password for ${SAMBA_USER}"
  (echo "${SAMBA_PASSWORD}"; echo "${SAMBA_PASSWORD}") | smbpasswd -s "${SAMBA_USER}"
else
  log "Creating Samba user ${SAMBA_USER}"
  (echo "${SAMBA_PASSWORD}"; echo "${SAMBA_PASSWORD}") | smbpasswd -s -a "${SAMBA_USER}"
fi
smbpasswd -e "${SAMBA_USER}" >/dev/null 2>&1 || true

log "Configuring Samba share ${SAMBA_SHARE_NAME} at ${SAMBA_SHARE_PATH}"

cat <<CFG > /etc/samba/smb.conf
[global]
   workgroup = ${SAMBA_WORKGROUP}
   server string = ${SAMBA_NETBIOS_NAME}
   netbios name = ${SAMBA_NETBIOS_NAME}
   security = user
   map to guest = bad user
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000
   server role = standalone server
   passdb backend = tdbsam
   load printers = no
   printing = bsd
   disable spoolss = yes
   obey pam restrictions = yes
   socket options = TCP_NODELAY
   interfaces = 0.0.0.0/0
   bind interfaces only = no

[${SAMBA_SHARE_NAME}]
   path = "${SAMBA_SHARE_PATH}"
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${SAMBA_USER}
   force user = root
   create mask = 0664
   directory mask = 0775
   inherit permissions = yes
   ea support = yes
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
CFG

log "Starting nmbd"
rm -f /run/samba/*.pid /var/run/samba/*.pid 2>/dev/null || true
nmbd -D
log "Starting smbd"
exec smbd --foreground --no-process-group

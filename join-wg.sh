#!/usr/bin/env bash

# this script depends on wireguard-tools, python3 and curl

if test $EUID -ne 0
then
  echo "Please run with root permissions"
  exit 1
fi

if test -z "${2}"
then
  if test -f /etc/wireguard/wg0.conf
  then
    echo "/etc/wireguard/wg0.conf already exists. You must specify an interface manually"
    exit 2
  fi
fi

FIX_WG_QUICK="true"
PEER=${1:-google.com}
IFACE=${2:-wg0}

fix_wg_quick(){
  # fix the wg-quick service file because it's not robust enough
  local _broken_service_file="/usr/lib/systemd/system/wg-quick@.service"
  local _fixed_service_file=$(dirname "${_broken_service_file}")/wg-quick-fixed@.service
  cp -f "${_broken_service_file}" "${_fixed_service_file}"
  sed 's,^[Unit],[Unit]\nStartLimitBurst=0,g' -i "${_fixed_service_file}"
  sed 's,^[Service],[Service]\nRestart=on-failure\nRestartSec=3,g' -i "${_fixed_service_file}"
  systemctl daemon-reload
}

curl -fsSL -o /bin/wg-request https://raw.githubusercontent.com/greyltc/wg-request/master/wg-request >/dev/null 2>/dev/null
chmod +x /bin/wg-request >/dev/null 2>/dev/null

wg genkey | tee /tmp/peer_A.key | wg pubkey > /tmp/peer_A.pub
timeout 5 python3 /bin/wg-request --private-key $(cat /tmp/peer_A.key) $(cat /tmp/peer_A.pub) "${PEER}" > "/etc/wireguard/${IFACE}.conf" 2>/dev/null
rslt=$?
rm /tmp/peer_A.key >/dev/null 2>/dev/null
rm /tmp/peer_A.pub >/dev/null 2>/dev/null
if test "${rslt}" = "0"
then
  echo "New config written to /etc/wireguard/${IFACE}.conf"
  cat "/etc/wireguard/${IFACE}.conf"
  wg-quick down "${IFACE}" >/dev/null 2>/dev/null
  wg-quick up "${IFACE}" >/dev/null 2>/dev/null
  if test "${FIX_WG_QUICK}" = "true"
  then
    fix_wg_quick
    systemctl enable "wg-quick-fixed@${IFACE}" >/dev/null 2>/dev/null
  else
    systemctl enable "wg-quick@${IFACE}" >/dev/null 2>/dev/null
  fi
  rslt=0
else
  echo "New config NOT written to /etc/wireguard/${IFACE}.conf"
  rm "/etc/wireguard/${IFACE}.conf"
fi
exit ${rslt}

#!/usr/bin/env bash

set -e
[ -z "${WORK_PATH}" ] || [ ! -d "${WORK_PATH}/include" ] && WORK_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. "${WORK_PATH}/include/functions.sh"
. "${WORK_PATH}/include/addons.sh"

[ -z "${LOADER_DISK}" ] && die "$(TEXT "Loader is not init!")"
checkBootLoader || die "$(TEXT "The loader is corrupted, please rewrite it!")"

# Shows title
clear
COLUMNS=$(ttysize 2>/dev/null | awk '{print $1}')
COLUMNS=${COLUMNS:-80}
TITLE="$(printf "$(TEXT "Welcome to %s")" "$([ -z "${RR_RELEASE}" ] && echo "${RR_TITLE}" || echo "${RR_TITLE}(${RR_RELEASE})")")"
DATE="$(date)"
printf "\033[1;44m%*s\n" "${COLUMNS}" ""
printf "\033[1;44m%*s\033[A\n" "${COLUMNS}" ""
printf "\033[1;31m%*s\033[0m\n" "$(((${#TITLE} + ${COLUMNS}) / 2))" "${TITLE}"
printf "\033[1;44m%*s\033[A\n" "${COLUMNS}" ""
printf "\033[1;32m%*s\033[0m\n" "${COLUMNS}" "${DATE}"

# Get first MAC address
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep -v lo) || true
# No network devices
[ "$(echo "${ETHX}" | wc -w)" -le 0 ] && die "$(TEXT "Network devices not found! Please re execute init.sh after connecting to the network!")"

# If user config file not exists, initialize it
if [ ! -f "${USER_CONFIG_FILE}" ]; then
  touch "${USER_CONFIG_FILE}"
fi

initConfigKey "kernel" "official" "${USER_CONFIG_FILE}"
initConfigKey "rd-compressed" "false" "${USER_CONFIG_FILE}"
initConfigKey "satadom" "2" "${USER_CONFIG_FILE}"
initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
initConfigKey "dsmlogo" "true" "${USER_CONFIG_FILE}"
initConfigKey "directboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "prerelease" "false" "${USER_CONFIG_FILE}"
initConfigKey "bootwait" "10" "${USER_CONFIG_FILE}"
initConfigKey "bootipwait" "10" "${USER_CONFIG_FILE}"
initConfigKey "kernelway" "power" "${USER_CONFIG_FILE}"
initConfigKey "kernelpanic" "5" "${USER_CONFIG_FILE}"
initConfigKey "odp" "false" "${USER_CONFIG_FILE}"
initConfigKey "hddsort" "false" "${USER_CONFIG_FILE}"
initConfigKey "usbasinternal" "false" "${USER_CONFIG_FILE}"
initConfigKey "emmcboot" "false" "${USER_CONFIG_FILE}"
initConfigKey "platform" "" "${USER_CONFIG_FILE}"
initConfigKey "model" "" "${USER_CONFIG_FILE}"
initConfigKey "modelid" "" "${USER_CONFIG_FILE}"
initConfigKey "productver" "" "${USER_CONFIG_FILE}"
initConfigKey "buildnum" "" "${USER_CONFIG_FILE}"
initConfigKey "smallnum" "" "${USER_CONFIG_FILE}"
initConfigKey "paturl" "" "${USER_CONFIG_FILE}"
initConfigKey "patsum" "" "${USER_CONFIG_FILE}"
initConfigKey "sn" "" "${USER_CONFIG_FILE}"
initConfigKey "mac1" "" "${USER_CONFIG_FILE}"
initConfigKey "mac2" "" "${USER_CONFIG_FILE}"
initConfigKey "layout" "qwerty" "${USER_CONFIG_FILE}"
initConfigKey "keymap" "" "${USER_CONFIG_FILE}"
initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
if [ -z "$(readConfigMap "addons" "${USER_CONFIG_FILE}")" ]; then
  initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.trivial" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.vmtools" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.mountloader" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.powersched" "" "${USER_CONFIG_FILE}"
  initConfigKey "addons.reboottoloader" "" "${USER_CONFIG_FILE}"
fi
initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
initConfigKey "modblacklist" "evbug,cdc_ether" "${USER_CONFIG_FILE}"

# for update
if [ -f "${PART2_PATH}/GRUB_VER" ]; then
  PLATFORMTMP="$(_get_conf_kv "PLATFORM" "${PART2_PATH}/GRUB_VER")"
  MODELTMP="$(_get_conf_kv "MODEL" "${PART2_PATH}/GRUB_VER")"
  [ -z "$(readConfigKey "platform" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "platform" "${PLATFORMTMP,,}" "${USER_CONFIG_FILE}"
  [ -z "$(readConfigKey "model" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "model" "$(echo "${MODELTMP}" | sed 's/d$/D/; s/rp$/RP/; s/rp+/RP+/')" "${USER_CONFIG_FILE}"
  [ -z "$(readConfigKey "modelid" "${USER_CONFIG_FILE}")" ] &&
    writeConfigKey "modelid" "${MODELTMP}" "${USER_CONFIG_FILE}"
fi

if [ ! "LOCALBUILD" = "${LOADER_DISK}" ]; then
  if arrayExistItem "sortnetif:" "$(readConfigMap "addons" "${USER_CONFIG_FILE}")"; then
    _sort_netif "$(readConfigKey "addons.sortnetif" "${USER_CONFIG_FILE}")"
  fi
  for N in ${ETHX}; do
    MACR="$(cat /sys/class/net/${N}/address 2>/dev/null | sed 's/://g')"
    IPR="$(readConfigKey "network.${MACR}" "${USER_CONFIG_FILE}")"
    if [ -n "${IPR}" ] && [ "1" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      IFS='/' read -r -a IPRA <<<"${IPR}"
      ip addr flush dev "${N}"
      ip addr add "${IPRA[0]}/${IPRA[1]:-"255.255.255.0"}" dev "${N}"
      if [ -n "${IPRA[2]}" ]; then
        ip route add default via "${IPRA[2]}" dev "${N}"
      fi
      if [ -n "${IPRA[3]:-${IPRA[2]}}" ]; then
        sed -i "/nameserver ${IPRA[3]:-${IPRA[2]}}/d" /etc/resolv.conf
        echo "nameserver ${IPRA[3]:-${IPRA[2]}}" >>/etc/resolv.conf
      fi
      sleep 1
    fi
    [ "${N::4}" = "wlan" ] && connectwlanif "${N}" 1 && sleep 1
    [ "${N::3}" = "eth" ] && ethtool -s "${N}" wol g 2>/dev/null || true
    # [ "${N::3}" = "eth" ] && ethtool -K ${N} rxhash off 2>/dev/null || true
  done
fi

# Get the VID/PID if we are in USB
VID="0x46f4"
PID="0x0001"
TYPE="DoM"
BUS=$(getBus "${LOADER_DISK}")

BUSLIST="usb sata sas scsi nvme mmc ide virtio vmbus xen"
if [ "${BUS}" = "usb" ]; then
  VID="0x$(udevadm info --query property --name "${LOADER_DISK}" 2>/dev/null | grep "ID_VENDOR_ID" | cut -d= -f2)"
  PID="0x$(udevadm info --query property --name "${LOADER_DISK}" 2>/dev/null | grep "ID_MODEL_ID" | cut -d= -f2)"
  TYPE="flashdisk"
elif ! echo "${BUSLIST}" | grep -wq "${BUS}"; then
  if [ "LOCALBUILD" = "${LOADER_DISK}" ]; then
    echo "LOCALBUILD MODE"
    TYPE="PC"
  else
    die "$(printf "$(TEXT "The boot disk does not support the current %s, only %s DoM is supported.")" "${BUS}" "${BUSLIST// /\/}")"
  fi
fi

# Save variables to user config file
writeConfigKey "vid" "${VID}" "${USER_CONFIG_FILE}"
writeConfigKey "pid" "${PID}" "${USER_CONFIG_FILE}"

# Inform user
printf "%s \033[1;32m%s (%s %s)\033[0m\n" "$(TEXT "Loader disk:")" "${LOADER_DISK}" "${BUS^^}" "${TYPE}"

# Load keymap name
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"

# Loads a keymap if is valid
if [ -f "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" ]; then
  printf "%s \033[1;32m%s/%s\033[0m\n" "$(TEXT "Loading keymap:")" "${LAYOUT}" "${KEYMAP}"
  zcat "/usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz" | loadkeys
fi

# Decide if boot automatically
BOOT=1
if ! loaderIsConfigured; then
  printf "\033[1;33m%s\033[0m\n" "$(TEXT "Loader is not configured!")"
  BOOT=0
elif grep -q "IWANTTOCHANGETHECONFIG" /proc/cmdline; then
  printf "\033[1;33m%s\033[0m\n" "$(TEXT "User requested edit settings.")"
  BOOT=0
fi

# If is to boot automatically, do it
if [ ${BOOT} -eq 1 ]; then
  "${WORK_PATH}/boot.sh" && exit 0
fi

HTTP=$(grep -i '^HTTP_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)
DUFS=$(grep -i '^DUFS_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)
TTYD=$(grep -i '^TTYD_PORT=' /etc/rrorg.conf 2>/dev/null | cut -d'=' -f2)

# Wait for an IP
printf "$(TEXT "Detected %s network cards.\n")" "$(echo "${ETHX}" | wc -w)"
printf "$(TEXT "Checking Connect.")"
COUNT=0
while [ ${COUNT} -lt 30 ]; do
  MSG=""
  for N in ${ETHX}; do
    if [ "1" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      MSG+="${N} "
    fi
  done
  if [ -n "${MSG}" ]; then
    printf "\r%s%s                  \n" "${MSG}" "$(TEXT "connected.")"
    break
  fi
  COUNT=$((COUNT + 1))
  printf "."
  sleep 1
done

[ ! -f /var/run/dhcpcd/pid ] && /etc/init.d/S41dhcpcd restart >/dev/null 2>&1 || true

printf "$(TEXT "Waiting IP.\n")"
for N in ${ETHX}; do
  COUNT=0
  DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
  MAC=$(cat /sys/class/net/${N}/address 2>/dev/null)
  printf "%s(%s): " "${N}" "${MAC}@${DRIVER}"
  while true; do
    if [ -z "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "DOWN")"
      break
    fi
    if [ "0" = "$(cat /sys/class/net/${N}/carrier 2>/dev/null)" ]; then
      printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "NOT CONNECTED")"
      break
    fi
    if [ ${COUNT} -eq 15 ]; then # Under normal circumstances, no errors should occur here.
      printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "TIMEOUT (Please check the IP on the router.)")"
      break
    fi
    COUNT=$((COUNT + 1))
    IP="$(getIP "${N}")"
    if [ -n "${IP}" ]; then
      if echo "${IP}" | grep -q "^169\.254\."; then
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(TEXT "LINK LOCAL (No DHCP server detected.)")"
      else
        printf "\r%s(%s): %s\n" "${N}" "${MAC}@${DRIVER}" "$(printf "$(TEXT "Access \033[1;34mhttp://%s:%d\033[0m to configure the loader via web terminal.")" "${IP}" "${TTYD:-7681}")"
      fi
      break
    fi
    printf "."
    sleep 1
  done
done

# Inform user
printf "\n"
printf "$(TEXT "Call \033[1;32minit.sh\033[0m to re get init info\n")"
printf "$(TEXT "Call \033[1;32mmenu.sh\033[0m to configure loader\n")"
printf "\n"
printf "$(TEXT "User config is on \033[1;32m%s\033[0m\n")" "${USER_CONFIG_FILE}"
printf "$(TEXT "HTTP: \033[1;34mhttp://%s:%d\033[0m\n")" "rr" "${HTTP:-7080}"
printf "$(TEXT "DUFS: \033[1;34mhttp://%s:%d\033[0m\n")" "rr" "${DUFS:-7304}"
printf "$(TEXT "TTYD: \033[1;34mhttp://%s:%d\033[0m\n")" "rr" "${TTYD:-7681}"
printf "\n"
if [ -f "/etc/shadow-" ]; then
  printf "$(TEXT "SSH port is \033[1;31m%d\033[0m, The \033[1;31mroot\033[0m password has been changed\n")" "22"
else
  printf "$(TEXT "SSH port is \033[1;31m%d\033[0m, The \033[1;31mroot\033[0m password is \033[1;31m%s\033[0m\n")" "22" "rr"
fi
printf "\n"

DSMLOGO="$(readConfigKey "dsmlogo" "${USER_CONFIG_FILE}")"
if [ "${DSMLOGO}" = "true" ] && [ -c "/dev/fb0" ] && [ ! "LOCALBUILD" = "${LOADER_DISK}" ]; then
  IP="$(getIP)"
  echo "${IP}" | grep -q "^169\.254\." && IP=""
  [ -n "${IP}" ] && URL="http://${IP}:${TTYD:-7681}" || URL="http://rr:${TTYD:-7681}"
  python3 "${WORK_PATH}/include/functions.py" makeqr -d "${URL}" -l "0" -o "${TMP_PATH}/qrcode_init.png"
  [ -f "${TMP_PATH}/qrcode_init.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_init.png" >/dev/null 2>/dev/null || true

  python3 "${WORK_PATH}/include/functions.py" makeqr -f "${WORK_PATH}/include/qhxg.png" -l "7" -o "${TMP_PATH}/qrcode_qhxg.png"
  [ -f "${TMP_PATH}/qrcode_qhxg.png" ] && echo | fbv -acufi "${TMP_PATH}/qrcode_qhxg.png" >/dev/null 2>/dev/null || true
fi

# Check memory
RAM=$(awk '/MemTotal:/ {printf "%.0f", $2 / 1024}' /proc/meminfo 2>/dev/null)
if [ "${RAM:-0}" -le 3500 ]; then
  printf "\033[1;33m%s\033[0m\n" "$(TEXT "You have less than 4GB of RAM, if errors occur in loader creation, please increase the amount of memory.")"
fi

mkdir -p "${CKS_PATH}"
mkdir -p "${LKMS_PATH}"
mkdir -p "${ADDONS_PATH}"
mkdir -p "${MODULES_PATH}"

exit 0

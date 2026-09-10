#!/usr/bin/env bash
set -euo pipefail

# Privilege setup for the Omarchy "NitroSense" bar widget
# (io.github.bobster05.nitrosense).
#
# The widget talks to the Acer embedded controller (EC) to read temperatures,
# fan speeds and to switch fan modes. The EC is reached through /dev/ec from
# the acpi_ec kernel module. These devices are root-only by default, so this
# script grants *group* access (group `nitro`) via udev rules instead of
# running the widget as root.
#
#   install:    sudo setup.sh
#   uninstall:  sudo setup.sh --uninstall
#
# After install, add your user to the `nitro` group and re-login:
#   sudo usermod -aG nitro $USER

UCONF=/etc/modules-load.d/nitro-ec.conf
URULE=/etc/udev/rules.d/99-nitro-ec.rules
URULE_DMI=/etc/udev/rules.d/99-nitro-dmi.rules

umask 022

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 [--uninstall]" >&2
  exit 1
fi

uninstall() {
  rm -f "$URULE" "$URULE_DMI" "$UCONF"
  udevadm control --reload-rules || true
  udevadm trigger || true
  rmmod acpi_ec 2>/dev/null || true
  echo "Removed: $URULE, $URULE_DMI, $UCONF"
  echo "Optional: sudo groupdel nitro  (after no member needs the EC)"
  echo "Done. Runtime /dev/ec access is revoked; the widget degrades gracefully."
}

[[ ${1:-} == "--uninstall" ]] && uninstall && exit 0

if ! grep -q '^nitro:' /etc/group; then
  groupadd nitro
  echo "created group 'nitro'"
fi

# /dev/ec comes from the acpi_ec kernel module. Keep it loaded on every boot.
printf 'acpi_ec\n' > "$UCONF"
echo "set: $UCONF"

# Udev rules grant members of group 'nitro' RW access to the EC and the
# DMI firmware (used to identify the EC firmware type), without sudo.
cat > "$URULE" <<'EOF'
KERNEL=="ec", MODE="0660", GROUP="nitro"
SUBSYSTEM=="debugfs", KERNEL=="io", RUN+="/bin/sh -c 'chmod 0660 /sys/kernel/debug/ec/ec0/io && chgrp nitro /sys/kernel/debug/ec/ec0/io'"
EOF
cat > "$URULE_DMI" <<'EOF'
SUBSYSTEM=="firmware", KERNEL=="DMI", GROUP="nitro", MODE="0440"
SUBSYSTEM=="firmware", KERNEL=="smbios_entry_point", GROUP="nitro", MODE="0440"
EOF
echo "set: $URULE, $URULE_DMI"

modprobe acpi_ec
udevadm control --reload-rules
udevadm trigger

if [[ -e /dev/ec ]]; then
  chgrp nitro /dev/ec 2>/dev/null || true
  chmod 0660 /dev/ec 2>/dev/null || true
  echo "ok: /dev/ec ready — $(ls -l /dev/ec | awk '{print $1, $3, $4}')"
else
  echo "error: /dev/ec still missing after modprobe acpi_ec." >&2
  exit 1
fi

echo
echo "Ready. Add your user to 'nitro' and re-login:"
echo "  sudo usermod -aG nitro \$USER"
echo "Then test with: $PWD/nitro-ec status"
#!/bin/sh

# Locate default vpnc-script
VPNC_SCRIPT="/etc/vpnc/vpnc-script"
if [ ! -f "$VPNC_SCRIPT" ]; then
	VPNC_SCRIPT="/usr/share/vpnc-scripts/vpnc-script"
fi

if [ -f "$VPNC_SCRIPT" ]; then
	# Execute standard vpnc network configuration as subprocess
	"$VPNC_SCRIPT" "$@" || true
else
	echo "[WARN] vpnc-script not found, proceeding without standard vpnc network setup" >&2
fi

# When connection is established or re-established, trigger NAT & SOCKS5 setup
case "$reason" in
connect | reconnect)
	if [ -x /usr/local/bin/setup-nat.sh ]; then
		/usr/local/bin/setup-nat.sh || true
	fi
	;;
esac

exit 0

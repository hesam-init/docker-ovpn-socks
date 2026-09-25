#!/usr/bin/env bash
# No -e: a vpnc-script failure must not stop the NAT setup below
set -uo pipefail

# shellcheck source=lib/common.sh
source /usr/local/lib/vpn-socks/common.sh

# Locate default vpnc-script
VPNC_SCRIPT=/etc/vpnc/vpnc-script
if [[ ! -f $VPNC_SCRIPT ]]; then
	VPNC_SCRIPT=/usr/share/vpnc-scripts/vpnc-script
fi

if [[ -f $VPNC_SCRIPT ]]; then
	# Execute standard vpnc network configuration as subprocess
	"$VPNC_SCRIPT" "$@" || true
else
	warn "vpnc-script not found, proceeding without standard vpnc network setup"
fi

# When connection is established or re-established, trigger NAT & SOCKS5 setup
case "${reason:-}" in
connect | reconnect)
	if [[ -x /usr/local/bin/tunnel-up.sh ]]; then
		/usr/local/bin/tunnel-up.sh || true
	fi
	;;
esac

exit 0

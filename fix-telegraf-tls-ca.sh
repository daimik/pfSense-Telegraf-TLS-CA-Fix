#!/bin/sh
# fix-telegraf-tls-ca.sh
# Patch the pfSense Telegraf package generator to emit tls_ca instead of the
# obsolete ssl_ca option, regenerate telegraf.conf and restart Telegraf.
#
# Run on pfSense as root:  sh fix-telegraf-tls-ca.sh
# Safe to run repeatedly.

set -eu

INC=/usr/local/pkg/telegraf.inc
CONF=/usr/local/etc/telegraf.conf
BACKUP=/root/telegraf.inc.orig
LOG=/var/log/telegraf/telegraf.log

die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -f "$INC" ]        || die "$INC not found. Is the Telegraf package installed?"
command -v php >/dev/null 2>&1 || die "php not found. Is this pfSense?"

# 1. Backup (keep the first one, it is the unmodified original)
if [ -f "$BACKUP" ]; then
    echo "Backup exists, keeping it: $BACKUP"
else
    cp -p "$INC" "$BACKUP"
    echo "Backup written: $BACKUP"
fi

# 2. Patch generator
if grep -q 'ssl_ca = ' "$INC"; then
    sed -i '' 's/ssl_ca = /tls_ca = /' "$INC"
    echo "Patched: ssl_ca -> tls_ca in $INC"
else
    echo "No ssl_ca in $INC (already patched or fixed upstream)"
fi

grep -q 'ssl_ca = ' "$INC" && die "ssl_ca still present in $INC after patch"
grep -n 'tls_ca' "$INC" || echo "Note: no tls_ca in $INC (package may not emit a CA line at all)"

# 3. Regenerate config
php -r 'require_once("/usr/local/pkg/telegraf.inc"); telegraf_resync_config();'
echo "Regenerated $CONF"

if grep -n 'ssl_ca' "$CONF"; then
    die "ssl_ca still present in $CONF"
fi
grep -n 'tls_ca' "$CONF" || echo "Note: no tls_ca in $CONF (no CA in cert manager, nothing to fix)"

# 4. Restart (packages are not enabled in rc.conf, so 'restart' refuses)
service telegraf onerestart || true
echo "Waiting 30 s for Telegraf to settle..."
sleep 30

if pgrep -x telegraf >/dev/null 2>&1; then
    echo "OK: Telegraf is running"
else
    echo "Telegraf is NOT running. Last log lines:" >&2
    [ -f "$LOG" ] && tail -n 20 "$LOG" >&2
    exit 1
fi

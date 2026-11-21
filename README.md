# pfSense Telegraf Package: ssl_ca Config Error Fix

The pfSense Telegraf package generates an InfluxDB output block with the obsolete option `ssl_ca`. Current Telegraf builds reject unknown options, so the config fails to load and Telegraf stops sending data to InfluxDB. This repo documents the cause and provides a fix script you can safely run more than once.

## Tested Hardware

| Property | Value |
|---|---|
| Device | Netgate 4200 |
| Firmware | pfSense Plus 26.07 |
| Package | Telegraf (pfSense package) |
| Output | InfluxDB over plain HTTP |
| Fixed | 2026-11-02 |

## Overview

Telegraf fails to load its config after every regeneration (boot, package sync, **Save** in *Services > Telegraf*) and stops sending data. Your Grafana pfSense dashboard goes flat at the time of the last regeneration.

The fix renames one option in the package's config generator. The `.ca` file the package writes is fine, only the option name is wrong.

## Table of Contents

- [Symptom](#symptom)
- [Root Cause](#root-cause)
- [Am I Affected?](#am-i-affected)
- [Fix](#fix)
  - [Option A: Script](#option-a-script)
  - [Option B: Manual](#option-b-manual)
- [Gotchas](#gotchas)
- [Verify](#verify)
- [When to Re-apply](#when-to-re-apply)
- [Undo](#undo)
- [Contributing](#contributing)
- [License](#license)

## Symptom

In `/var/log/telegraf/telegraf.log`:

```
E! loading config file /usr/local/etc/telegraf.conf failed: plugin outputs.influxdb: line 30:
configuration specified the fields ["ssl_ca"], but they were not used; this is either a typo
or this config option does not exist in this version
```

## Root Cause

`/usr/local/pkg/telegraf.inc` writes

```
ssl_ca = "/usr/local/etc/telegraf.ca"
```

into the InfluxDB output block whenever the pfSense certificate manager contains **any** CA (`if (count($a_ca))`), regardless of whether the output URL is HTTP or HTTPS. A CA from an OpenVPN client, a VPN provider or an internal CA is enough to trigger it.

Telegraf renamed `ssl_ca` to `tls_ca` years ago, and current builds refuse unknown options instead of ignoring them.

| Issue | Status |
|---|---|
| Option name is outdated (`ssl_ca` instead of `tls_ca`) | Fixed by this repo |
| CA line is emitted even for `http://` outputs | Harmless once the name is correct, upstream should fix |

## Am I Affected?

Run on pfSense (*Diagnostics > Command Prompt* or SSH, option 8):

```
grep -n -E 'ssl_ca|tls_ca' /usr/local/etc/telegraf.conf
tail -n 20 /var/log/telegraf/telegraf.log
```

`ssl_ca` in the config plus the error above in the log means yes.

## Fix

### Option A: Script

Run on pfSense as root:

```
fetch -o /root/fix-telegraf-tls-ca.sh https://raw.githubusercontent.com/daimik/pfSense-Telegraf-TLS-CA-Fix/main/fix-telegraf-tls-ca.sh
sh /root/fix-telegraf-tls-ca.sh
```

Read the script before running it. It:

- backs up `/usr/local/pkg/telegraf.inc` to `/root/telegraf.inc.orig` (only once, the first backup is kept)
- replaces `ssl_ca = ` with `tls_ca = ` in the generator
- regenerates `/usr/local/etc/telegraf.conf` and restarts Telegraf
- verifies the result and exits non-zero if anything looks wrong

You can run it again safely. If the generator is already patched, it only regenerates and restarts.

### Option B: Manual

Run on pfSense as root.

Patch the generator:

```
cp /usr/local/pkg/telegraf.inc /root/telegraf.inc.orig
sed -i '' 's/ssl_ca = /tls_ca = /' /usr/local/pkg/telegraf.inc
grep -n 'tls_ca' /usr/local/pkg/telegraf.inc
# expect one line similar to:  $cfg .= "\ttls_ca = \"" . $ca_pem_file . "\"\n";
```

Regenerate and restart:

```
php -r 'require_once("/usr/local/pkg/telegraf.inc"); telegraf_resync_config();'
grep -n -E 'ssl_ca|tls_ca' /usr/local/etc/telegraf.conf   # expect tls_ca only
service telegraf onerestart
sleep 30; service telegraf status                          # expect running
```

Instead of the `php -r` line you can also click **Save** in *Services > Telegraf*.

## Gotchas

- `service telegraf restart` refuses because pfSense packages are not enabled in `/etc/rc.conf`. Use `onerestart`.
- The pfSense root shell is tcsh, and BSD `sed` does not understand `\t`. That is why the pattern has no tab in it.
- `sed -i ''` is the BSD syntax. GNU-style `sed -i` without the empty string fails on pfSense.

## Verify

```
service telegraf status
grep -n tls_ca /usr/local/etc/telegraf.conf
tail -n 20 /var/log/telegraf/telegraf.log
```

Grafana should show fresh points within one minute.

## When to Re-apply

> **⚠️ Package Upgrade Warning:** The patch lives in the package file, so it survives reboots and config saves, but a Telegraf package upgrade or reinstall overwrites it.

Symptom after an upgrade: Telegraf not running, same error in `/var/log/telegraf/telegraf.log`. Re-run the script, or:

```
sed -i '' 's/ssl_ca = /tls_ca = /' /usr/local/pkg/telegraf.inc
```

then **Save** in *Services > Telegraf*.

Once the package itself is fixed upstream, the `sed` matches nothing and becomes a no-op.

## Undo

```
cp /root/telegraf.inc.orig /usr/local/pkg/telegraf.inc
php -r 'require_once("/usr/local/pkg/telegraf.inc"); telegraf_resync_config();'
service telegraf onerestart
```

Or reinstall the package from *System > Package Manager*.

## Contributing

Tested on a different pfSense version or Netgate model? Open an issue or PR with your version and result so the Tested Hardware table can grow.

If this saved you time, add a note on the [pfSense bug tracker](https://redmine.pfsense.org) so the package gets fixed properly: `tls_ca` instead of `ssl_ca`, and only emit it for `https://` outputs.

## License

MIT, see [LICENSE](LICENSE).

This fix is provided as-is, without warranty, for educational and interoperability purposes. You are patching a file owned by a pfSense package, so keep the backup. pfSense and Netgate are trademarks of Rubicon Communications, LLC (Netgate). Telegraf and InfluxDB are trademarks of InfluxData. This project is not affiliated with or endorsed by Netgate or InfluxData.

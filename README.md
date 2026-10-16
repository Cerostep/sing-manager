# sing-manager

sing-manager is an interactive installation and management script for sing-box on
Debian and Ubuntu. It generates a VLESS + Reality configuration and can optionally
install Nginx to host a local camouflage website.

## Deployment modes

Both modes use sing-box for the VLESS + Reality inbound. Select the mode by editing
`SELF_BACKEND` in the configuration section at the top of `singmanager`.

### External camouflage site (default)

Set `SELF_BACKEND="false"`. Nginx is not installed or configured. Reality uses
`FAKE_SITE` and `FAKE_SITE_PORT` as its handshake destination; the defaults are
`cdnjs.cloudflare.com` and `443`. sing-box listens on TCP port `443`.

### Local Nginx camouflage site

Set `SELF_BACKEND="true"`. The script installs Nginx and downloads its site files and
configuration from `NGINX_RELEASE_URL`. The included Nginx configuration listens on
`127.0.0.1:18443` with TLS, while sing-box listens on TCP port `443`. Reality uses
the local Nginx listener (`127.0.0.1:18443`) as its handshake destination. Configure
`SERVER_ADDR` with the public IP address or domain that clients use to reach
sing-box; point the domain to this server.

`ENABLE_WARPPLUS` is independent of the deployment mode. When set to `true`, the
script installs and configures Cloudflare WARP as an outbound proxy. Set it to
`false` to skip WARP.

## Warning: firewall and upstream access

With the default external-site mode (`SELF_BACKEND="false"`), `FAKE_SITE` defaults to
the CDN hostname `cdnjs.cloudflare.com` on TCP port `443`.

- **Traffic theft:** Attackers can pull large files through your server, consuming your bandwidth quota.
- **Overage or suspension:** Providers with metered bandwidth may charge you or suspend the instance.
- **Fingerprinting:** Abnormal fallback traffic makes your server easier to identify as a proxy.

**Recommended actions**

1. **Prefer a local camouflage target:**
   - enable self backend. (`SELF_BACKEND="true"`)
2. **Monitor traffic:** set daily bandwidth alerts (e.g. `vnstat`) and watch the connection count on port 443.

sing-box Reality servers have no built-in fallback rate limiting. You must rely on **firewall rules** (nftables/iptables) and, ideally, a **local camouflage target**.

## Nginx TLS certificate

The script does not request, issue, or install TLS certificates. For ACME, use a
DNS-01 challenge: Nginx listens on loopback port `18443`, so it cannot directly serve
the public HTTP-01 validation request on port `80`. DNS-01 proves control of the
domain by creating a TXT record under `_acme-challenge`. See the official
[Let's Encrypt challenge documentation](https://letsencrypt.org/docs/challenge-types/)
for the HTTP-01 and DNS-01 requirements.

The example below uses [acme.sh](https://github.com/acmesh-official/acme.sh) in manual
DNS mode. Replace `admin@example.com` with your email and `example.com` with a domain
you control. Run these commands as root:

```bash
sudo apt-get update
sudo apt-get install -y curl socat
sudo -i
curl https://get.acme.sh | sh -s email=admin@example.com
~/.acme.sh/acme.sh --issue -d example.com --dns \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please
```

The command prints the TXT record name and value. Add that record at your DNS provider
(the name is normally `_acme-challenge.example.com`), then wait until it is visible in
public DNS. Complete issuance by running:

```bash
~/.acme.sh/acme.sh --renew -d example.com \
  --yes-I-know-dns-manual-mode-enough-go-ahead-please
```

After successful issuance, install the certificate and private key at the paths
expected by this script:

```bash
install -d -m 700 /etc/nginx/ssl
~/.acme.sh/acme.sh --install-cert -d example.com \
  --key-file /etc/nginx/ssl/private.key \
  --fullchain-file /etc/nginx/ssl/fullchain.cer \
  --reloadcmd "nginx -t && systemctl enable nginx && (systemctl reload nginx || systemctl start nginx)"
```

`--install-cert` copies the managed certificate into the Nginx paths and saves the
deployment command for renewals. Manual DNS mode cannot renew unattended: each time
the certificate is due for renewal, add the newly requested TXT record, run the
documented `--renew` command again, and ensure the saved deployment hook succeeds.
For production, prefer an ACME DNS API plugin so issuance and renewal can update DNS
automatically. Configure the integration documented for your DNS provider, issue with
its `dns_<provider>` plugin, then run the same `--install-cert` command so renewed
files are deployed and Nginx is reloaded. Use a narrowly scoped DNS API token, protect
it as a secret, and do not put it in this repository. The acme.sh project also
documents DNS persist mode for providers without an API. See the
[acme.sh documentation](https://github.com/acmesh-official/acme.sh) and its
[manual DNS mode guide](https://github.com/acmesh-official/acme.sh/wiki/DNS-manual-mode)
for installation, DNS validation, certificate deployment, and renewal details.

The expected files are `/etc/nginx/ssl/fullchain.cer` (full chain) and
`/etc/nginx/ssl/private.key` (matching private key). Keep the private key readable
only by root.

If either file is missing or empty, the script warns and skips Nginx configuration
validation and startup, then continues the sing-box installation. If `nginx -t`
fails, or enabling/restarting Nginx fails, the script reports a warning and continues;
it does not repair Nginx automatically. After certificate deployment, you can validate
and start Nginx manually:

```bash
sudo nginx -t
sudo systemctl enable --now nginx
```

If Nginx still fails, inspect its error output and the installation log at
`/tmp/install.log`.

## Installation

The script requires Debian or Ubuntu and root privileges. Edit the configuration
values at the top of `singmanager` before installation. `SERVER_ADDR` may be set
manually. If it is left empty, the script displays a reminder at startup and tries
to detect the public IP during installation. If detection fails, you can enter the
public IP or domain manually, retry detection, or cancel installation without
exiting the manager.

Run the installer:

```bash
sudo bash singmanager
```

Choose option `0` from the main menu and confirm the prompts. On successful
installation, the script is copied to `/usr/local/bin/singmanager` and adds
`/usr/local/bin` to root's `.bashrc`. You can then launch the manager with:

```bash
sudo singmanager
```

## Management and generated files

The main menu provides service status, subscription and QR display, service controls,
and exit options.

- VLESS subscription: `/etc/sing-box/vless-subscription.txt`
- QR code SVG (256 x 256 px): `/etc/sing-box/vless-qr.svg`
- Installation log: `/tmp/install.log`

Selecting installation runs a health check instead of trusting the completion marker
alone. The check validates the sing-box binary and configuration, expected VLESS
inbound and port, systemd unit, subscription, 256 x 256 px QR file, required
dependencies, installed manager command, and root's `.bashrc` PATH entry. In local
Nginx mode, it also checks that Nginx and its main/site configurations are present. A
healthy installation is left intact and its QR code is displayed. If a check fails,
the script offers a repair installation that overwrites the managed sing-box
configuration and systemd unit and regenerates its subscription and QR code. The QR
code is displayed when repair completes successfully. The check also verifies that
`/etc/sing-box/config.json` links to the managed VLESS configuration; installations
still pointing to a legacy AnyTLS configuration are repaired to use VLESS.

To force a repair, remove `/etc/sing-box/installation_complete.flag` and select
installation from the menu.

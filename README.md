# sing-manager

sing-manager is an interactive installation and management script for sing-box on
Debian and Ubuntu. It generates a VLESS + Reality configuration and can optionally
install Nginx to host a local camouflage website.

## Quick Start

### Requirements

- A Debian or Ubuntu server with root or `sudo` access.
- An open inbound TCP port `443`.
- For local Nginx mode, a domain hosted on Cloudflare DNS. In external-site mode,
  the installer detects the server's public IPv4 address for the client connection.

### Install and configure

Clone the repository and edit the user configuration near the top of `singmanager`:

```bash
git clone https://github.com/Cerostep/sing-manager.git
cd sing-manager
vi singmanager
```

The default configuration uses an external Reality handshake site. Cloudflare WARP+
can be enabled by setting `ENABLE_WARPPLUS="true"`. Set `SELF_BACKEND` and
`ENABLE_WARPPLUS` to `"true"` or `"false"` as needed. In external-site mode, the
installer detects the server's public IPv4 address for the VLESS subscription. If
detection fails, it asks for a client connection address for that installation only.
If enabling the local Nginx backend, set `SELF_DOMAIN` to a domain you control and
`ACME_EMAIL` to an account contact address. The domain is used as the client
connection address; the installer requests and installs its Nginx certificate
automatically. See
[Nginx TLS certificate](#nginx-tls-certificate).

Run the interactive installer:

```bash
bash singmanager
```

Review and confirm the displayed configuration, choose `0` from the main menu, and
confirm the installation. The installer installs the supported sing-box version
`1.13.8` without prompting for a version. When asked whether to enable and start
sing-box, answer `Y`. The installer installs its dependencies, configures the VLESS +
Reality service, and creates a subscription link and QR code.

### Connect a client

After installation, run the manager and choose `2` to display the VLESS subscription
link and QR code:

```bash
/usr/local/bin/singmanager
```

Import the link into a compatible VLESS + Reality client, or scan the QR code from
`/etc/sing-box/vless-qr.svg`. The subscription link is also saved to
`/etc/sing-box/vless-subscription.txt`.

The server listens on TCP port `443`. It provides a VLESS + Reality endpoint, not a
regular HTTPS website; opening the server address in a browser is not a connectivity
test. Use a compatible client to connect.

## Deployment modes

Both modes use sing-box for the VLESS + Reality inbound. Select the mode by editing
`SELF_BACKEND` in the configuration section at the top of `singmanager`.

### External camouflage site (default)

Set `SELF_BACKEND="false"`. Nginx is not installed or configured. Reality uses
`cdnjs.cloudflare.com:443` as both its TLS server name (SNI) and handshake
destination. sing-box listens on TCP port `443`.

## Warning: firewall and upstream access

With the default external-site mode (`SELF_BACKEND="false"`), the Reality handshake
destination is `cdnjs.cloudflare.com` on TCP port `443`.

- **Traffic theft:** Attackers can pull large files through your server, consuming your bandwidth quota.
- **Overage or suspension:** Providers with metered bandwidth may charge you or suspend the instance.
- **Fingerprinting:** Abnormal fallback traffic makes your server easier to identify as a proxy.

**Recommended actions**

1. **Prefer a local camouflage target:**
   - enable self backend. (`SELF_BACKEND="true"`)
2. **Monitor traffic:** set daily bandwidth alerts (e.g. `vnstat`) and watch the connection count on port 443.

sing-box Reality servers have no built-in fallback rate limiting. You must rely on **firewall rules** (nftables/iptables) and, ideally, a **local camouflage target**.

### Local Nginx camouflage site

Set `SELF_BACKEND="true"`. The script installs Nginx and downloads its site files and
configuration from `NGINX_RELEASE_URL`, then requests a certificate for `SELF_DOMAIN`
using acme.sh and the Cloudflare DNS-01 API. The included Nginx configuration listens
on `127.0.0.1:18443` with TLS, while sing-box listens on TCP port `443`. Reality uses
`SELF_DOMAIN` as its TLS server name (SNI) and the local Nginx listener
(`127.0.0.1:18443`) as its handshake destination. Point the `SELF_DOMAIN` DNS record
to this server; the installer uses that domain as the client connection address.

`ENABLE_WARPPLUS` is independent of the deployment mode. When set to `true`, the
script installs and configures Cloudflare WARP as an outbound proxy. Set it to
`false` to skip WARP.


## Nginx TLS certificate

When `SELF_BACKEND="true"`, the installer uses
[acme.sh](https://github.com/acmesh-official/acme.sh) with Let's Encrypt DNS-01
validation through the Cloudflare DNS API. DNS-01 proves domain control by creating a
temporary TXT record under `_acme-challenge`; it works while Nginx is bound only to
loopback (`127.0.0.1:18443`).

Before installing:

1. Register a domain and use Cloudflare as its authoritative DNS provider.
2. Set `SELF_DOMAIN` to the hostname that should appear in the certificate and VLESS
   Reality SNI. The installer applies the same hostname to Nginx `server_name`.
3. Set `ACME_EMAIL` to an email address for the ACME account.
4. Create a Cloudflare API Token limited to the relevant zone with **Zone / DNS / Edit**
   and **Zone / Zone / Read** permissions. Do not put the token in this repository.

During installation, the script securely prompts for the token without echoing it.
acme.sh uses it to complete DNS-01 validation and saves the credential in its root
account configuration for scheduled renewals. The script installs the full chain at
`/etc/nginx/ssl/fullchain.cer` and the private key at
`/etc/nginx/ssl/private.key`, validates the hostname and key pair, tests the Nginx
configuration, and starts Nginx. Certificate renewal is scheduled by acme.sh; its
installation hook tests and reloads Nginx after successful renewal. Keep the root
account files and private key protected.

The domain in `SELF_DOMAIN` is used for certificate validation, Reality SNI, and the
client connection address. Make its DNS record point to the server. In external-site
mode the client connection address is detected from the public IPv4 address, or
entered temporarily if detection fails. The Cloudflare API token is only needed for
certificate issuance/renewal; never paste it into chat, logs, or source control.

If ACME issuance, certificate validation, `nginx -t`, or Nginx startup fails, the
installation stops rather than reporting a usable self-hosted backend. Inspect
`/tmp/install.log` for diagnostics and rerun the installer after resolving the cause.
For details about DNS-01, see the official
[Let's Encrypt challenge documentation](https://letsencrypt.org/docs/challenge-types/)
and the [acme.sh DNS API documentation](https://github.com/acmesh-official/acme.sh).
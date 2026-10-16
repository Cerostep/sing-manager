# sing-manager

sing-manager 是用于 Debian/Ubuntu 的 sing-box 安装与管理脚本。当前只生成
VLESS + Reality 配置，并可选择安装 Nginx 托管静态伪装站点。

## 部署架构

两种部署模式都由 sing-box 提供 VLESS + Reality 入站服务。sing-box 与 Nginx 的
监听端口按 `SELF_BACKEND` 配合设置：

### 1. 外部伪装站点（默认）

设置 `SELF_BACKEND="false"`。脚本不安装或配置 Nginx，Reality 握手使用
`FAKE_SITE` 和 `FAKE_SITE_PORT` 指定的外部站点（默认
`cdnjs.cloudflare.com:443`）。sing-box 直接监听 TCP `443`，适用于已有其他网站
或不需要本机托管伪装站点的场景。

### 2. 本机 Nginx 伪装站点

设置 `SELF_BACKEND="true"`。脚本安装 Nginx，并从 `NGINX_RELEASE_URL` 下载静态
站点和 Nginx 配置；Nginx 监听 HTTPS `443`，sing-box 改为监听 TCP `21443`，
避免端口冲突。Reality 握手使用 `SERVER_ADDR` 作为站点名。域名应解析到此服务器。

启用前需准备 Nginx TLS 证书文件：

- `/etc/nginx/ssl/fullchain.cer`
- `/etc/nginx/ssl/private.key`

脚本当前会配置并启动 Nginx，但不会在安装流程中自动签发证书；请在安装前准备好
证书及对应私钥。

简化结构：

```text
外部伪装模式：
客户端 ── VLESS + Reality / TCP 443 ──> sing-box ── Reality 握手 ──> 外部站点

本机 Nginx 模式：
客户端 ── VLESS + Reality / TCP 21443 ──> sing-box
客户端 ── HTTPS / TCP 443 ──────────────> Nginx 静态伪装站点
```

`ENABLE_WARPPLUS` 是独立于上述两种模式的选项：设为 `true` 时会安装并配置
Cloudflare WARP 代理出站；设为 `false` 时不安装 WARP。

## 安装

要求 Debian/Ubuntu 系统及 root 权限。先编辑 `singmanager` 顶部的用户配置项，
至少按所选模式填写 `SERVER_ADDR` 等参数，再运行：

```bash
sudo bash singmanager
```

按菜单选择 `0` 开始安装，并确认安装步骤中的提示。安装成功后，脚本会安装到
`/usr/local/bin/singmanager`，并将 `/usr/local/bin` 添加到 root 的 `.bashrc`。
之后可运行：

```bash
sudo singmanager
```

## 管理与输出

主菜单提供服务状态查看、订阅信息/二维码展示、服务控制和退出功能。生成的 VLESS
订阅链接保存在 `/etc/sing-box/vless-subscription.txt`；对应 SVG 二维码保存在
`/etc/sing-box/vless-qr.svg`，宽高均为 256 px。安装日志位于 `/tmp/install.log`。

安装成功后重复选择安装会跳过，避免重建配置。如确需重新安装，请删除
`/etc/sing-box/installation_complete.flag` 后再次运行安装。

# OpenCode Remote (Tailscale)

用一条命令，把 Windows 上的 **OpenCode** 变成手机可用的远程工作台。

手机浏览器扫码即可使用，**iPhone / 安卓都不用装 App**，地址**永久固定**，电脑重启也不变。

> **English**: [README.en.md](README.en.md)
>
> **已测试**：Windows 11 · OpenCode `2.2.5` · Tailscale `1.104.4` · PowerShell 5.1

---

## 为什么用 Tailscale，而不是 Cloudflare 临时隧道

Cloudflare **quick tunnel** 会缓冲 `text/event-stream`（SSE）。OpenCode 的 Web UI 依赖 SSE 初始化会话列表，结果就是：

- 页面能打开，但会话列表永远停在加载骨架
- 控制台反复报 `[global-sdk] event stream disconnected`
- 这是 Cloudflare 的已知限制（[cloudflared#1449](https://github.com/cloudflare/cloudflared/issues/1449)），官方明确说 quick tunnel 是 demo 用途

Tailscale 没有这个问题：Serve / Funnel 都是真正的流式代理，会话列表、工具输出、权限弹窗都正常。

---

## 架构

```
手机浏览器
   │ HTTPS
   ▼
Tailscale Funnel（公网入口，固定域名）
   │ WireGuard
   ▼
tailscaled（本机）
   │ HTTP
   ▼
OpenCode 后台服务 127.0.0.1:28894
```

- **Tailscale**：电脑主动向外建连，不需要公网 IP、不需要路由器端口映射、不需要关防火墙
- **Funnel**：把本机端口发布成公网 HTTPS，任何浏览器可访问（iPhone 无需 App）
- **Serve**：同一地址在 tailnet 内也可用（安卓装 Tailscale App 后走内网直连）
- **认证**：`opencode pair` 生成一次性链接（5 分钟 / 一次），打开后种下 30 天 cookie

---

## 要求

| 项 | 要求 |
|---|---|
| 系统 | Windows 10 / 11 |
| PowerShell | 5.1+（系统自带即可） |
| Node.js | 18+（仅用于 `npm install -g`） |
| OpenCode | `@opencode/cli`（测试版本 `2.2.5`） |
| Tailscale | 免费 Personal 账号即可，需登录 |
| 网络 | 能访问 `login.tailscale.com` 和 `*.ts.net` |

> 不需要 Python、不需要 Node 运行时（除了安装 OpenCode 本身）、不需要域名。

---

## 快速开始

### 1. 安装 OpenCode

```powershell
npm install -g @opencode/cli
opencode --version
```

### 2. 安装并登录 Tailscale

```powershell
winget install --id Tailscale.Tailscale -e
```

安装后从托盘图标登录（Google / Microsoft / GitHub 均可）。

### 3. 克隆并运行

```powershell
git clone https://github.com/logic77lhl/opencode-remote-tailscale.git
cd opencode-remote-tailscale
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

脚本会自动：

```
[1] 找到 OpenCode CLI
[2] 找到 Tailscale，确认已登录（未登录会打开登录页）
[3] 启动 OpenCode 后台服务
[4] 开启 Tailscale Serve，再开启 Funnel
    - 如果 tailnet 没启用，会打印/打开启用链接，等你按回车后重试
[5] 等待 HTTPS 可访问
[6] 写入登录自启（可选）
[7] 生成一次性登录链接 + 本地二维码页面
```

### 4. 手机扫码

用**系统相机**扫码（不要用微信/QQ 内置浏览器），打开后：

1. 自动登录并进入会话列表
2. Safari/Chrome → 分享 → **添加到主屏幕**
3. 以后点图标即可

固定地址形如：

```
https://<your-host>.<your-tailnet>.ts.net
```

---

## 日常使用

| 操作 | 说明 |
|---|---|
| 点主屏幕图标 | 直接进入，地址不变 |
| 切换对话 | 左侧 / 抽屉的会话列表 |
| 新建对话 | 右上角 |
| 发指令 | 底部输入框，支持语音 |
| 权限审批 | 工具调用会弹窗，点允许 / 拒绝 |
| 手机锁屏 / 断网 | 不影响，任务在电脑上继续跑 |
| 登录过期 | 30 天后重新跑 `restore.ps1` 扫码 |

### 电脑重启后

正常情况下会自动恢复：

```
Windows 启动 → Tailscale 服务上线 → Funnel 配置恢复
→ 登录 Windows → 自启脚本启动 OpenCode 服务 → 手机刷新即可
```

> ⚠️ 如果重启后停在 Windows 锁屏没人登录，OpenCode 服务不会启动，页面会 502。登录一次即可。

### 生成新的登录二维码

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1
```

- 电脑没装 Python 也能出二维码：仓库自带 `assets/qrcode.min.js`，本地渲染，不联网
- 不想弹二维码：`restore.ps1 -NoQr`，只打印链接
- 只想内网访问：`restore.ps1 -NoFunnel`

---

## 常用命令

```powershell
$ts = "C:\Program Files\Tailscale\tailscale.exe"

& $ts status                  # 设备与在线状态
& $ts ip -4                   # 本机 Tailscale IP
& $ts serve status            # Serve / Funnel 配置

& $ts funnel --bg 28894       # 开启公网 HTTPS
& $ts funnel --https=443 off  # 关闭公网入口（保留 Serve）
& $ts serve --bg 28894        # 仅内网 HTTPS

opencode service status       # OpenCode 服务状态
opencode service start        # 启动服务
opencode pair --url https://<your-host>.<your-tailnet>.ts.net
```

---

## 安全（务必读）

**OpenCode 的密码 = 你电脑的远程 shell 密码。** 拿到密码、配对链接或 30 天 cookie 的人，能以你的身份读写文件、执行命令。

关键事实：

- Funnel 的登录页是**公网可见**的（有密码保护）
- 密码 43 位随机时，暴力破解不可行
- 配对链接 **5 分钟、一次性**
- Cookie **30 天**，`HttpOnly`、`SameSite=Lax`
- **改密码会立即踢掉所有设备**（cookie 签名以密码为密钥）

最小加固清单：

1. 给 Tailscale 登录账号开 **2FA**
2. 不需要外网时关掉 Funnel：
   ```powershell
   & $ts funnel --https=443 off
   & $ts serve --bg 28894
   ```
3. 手机丢失：`opencode service set password "<新的随机密码>"`
4. 电脑开启 BitLocker；不要用管理员账号跑 OpenCode

完整安全说明见 [docs/SECURITY.md](docs/SECURITY.md)。

---

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

- 默认只移除登录自启
- 加 `-ResetIngress` 关闭 Serve / Funnel
- 加 `-StopService` 停止 OpenCode 服务
- **不会删除** OpenCode 会话数据

---

## 故障排查

见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

最常见的几个：

| 现象 | 处理 |
|---|---|
| `Importing a module script failed` | 删掉旧主屏幕图标；用 Safari/Chrome 打开；清站点数据 |
| 401 / 未认证 | 链接过期或已用过，重新跑 `restore.ps1` |
| 502 | OpenCode 服务没起来，跑 `restore.ps1` |
| `Funnel is not enabled` | 脚本会打印启用链接，点开启用后重试 |
| `Logged out` | `tailscale login` |
| 很慢 | 走公网 Funnel；安卓装 Tailscale App 可走内网直连 |

---

## 文件结构

```
.
├── assets/
│   ├── qrcode.min.js          # 本地二维码渲染（MIT, davidshimjs/qrcodejs）
│   └── NOTICE.md
├── docs/
│   ├── SECURITY.md
│   └── TROUBLESHOOTING.md
├── scripts/
│   ├── lib/common.ps1
│   ├── setup.ps1              # 一次性安装
│   ├── restore.ps1            # 恢复 + 新二维码
│   └── uninstall.ps1
├── LICENSE
└── README.md
```

---

## 已知限制

| 限制 | 说明 |
|---|---|
| 重启后需登录 Windows | 停在锁屏时自启脚本不运行 |
| Funnel 公网可见 | 有密码保护；不需要时关掉 |
| 公网入口有延迟 | 国内约 0.7~1.5 秒；内网直连更快 |
| 单点 | 电脑关机 / 断网即不可用 |
| 版本敏感 | `opencode service` / `pair` 的参数随版本可能变化，已在 2.2.5 验证 |

---

## License

MIT

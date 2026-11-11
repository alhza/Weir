# 协议全景：Loon / Quantumult X 实际支持什么

以官方文档为准，不以「大家都在说」为准。
来源：[Loon 单节点配置](https://nsloon.app/docs/Node/) · [Loon 订阅节点配置](https://nsloon.app/docs/Node/subscription)

---

## 一、Loon 原生协议

| 协议 | Loon 写法 | 订阅 URI | 传输扩展 | 关键点 |
| --- | --- | --- | --- | --- |
| Shadowsocks | `Shadowsocks` | `ss://` | Simple Obfs / ShadowTLS | 支持 2022-blake3 系列 |
| ShadowsocksR | `ShadowsocksR` | `ssr://` | ShadowTLS | 老协议，靠混淆续命 |
| HTTP | `http` | — | ShadowTLS | 明文，仅内网/中转 |
| HTTPS | `https` | — | — | `always-use-connect` |
| SOCKS5 | `socks5` | — | `over-tls` / ShadowTLS | 两者互斥 |
| VMess | `VMess` | `vmess://` | tcp / ws / http + Reality | `alterId=0` 才走 AEAD |
| VLESS | `VLESS` | `vless://` | tcp / ws / http + Reality | `flow=xtls-rprx-vision` |
| Trojan | `Trojan` | `trojan://` | tcp / ws + Reality | `transport=http` 按 ws 处理 |
| WireGuard | `WireGuard` | **无 URI** | — | 只能写标准格式，多 Peer |
| Hysteria 2 | `Hysteria2` | `hysteria2://` `hy2://` | QUIC | 端口跳跃、Salamander 混淆 |
| AnyTLS | `AnyTLS` | `anytls://` | — | 支持 Reality |
| 自定义 | `Custom` | — | `script-path=` | **用 JS 实现任意协议** |

### 通用参数（几乎所有协议都能吃）

| 参数 | 作用 | 什么时候必须配 |
| --- | --- | --- |
| `tls-profile` | TLS ClientHello 指纹：`chrome` / `chrome147` / `safari-ios18` / `safari-ios-26` / `default` / `global` | 节点被识别为「非浏览器握手」时 |
| `sni` | TLS SNI | Reality / 域名套 CDN 时 |
| `skip-cert-verify` | 跳过证书链验证 | 自签证书；**能用指纹就别用这个** |
| `tls-cert-sha256` / `tls-pubkey-sha256` | 证书 / 公钥固定 | 自签证书的正确做法，比 skip 安全 |
| `udp` | 允许 UDP 转发 | 游戏、语音、QUIC |
| `udp-over-tcp` | UDP 走 TCP | 节点 UDP 被 QoS 时 |
| `block-quic` | 阻断 QUIC | 想看 HTTPS 流量但被 h3 绕过时；**要转发 QUIC 就设 false** |
| `fast-open` | TCP Fast Open | 首包延迟敏感 |
| `ip-mode` | 解析节点域名的 IP 栈：`v4-only` / `dual` / `prefer-v4` / `prefer-v6` / `v6-only` | 节点域名有 AAAA 但 v6 不通时 |
| `server-dns` | 解析节点域名用独立 DNS（DoU/DoH/DoQ/DoH3） | 3.5.2+；节点域名被污染时 |

`server-dns` 是个被低估的参数。它只用于解析**节点服务器域名**，不影响普通请求。很多人节点连不上，是因为节点域名被污染——这时候不用换机场，配一个 `server-dns="https://dns.alidns.com/dns-query"` 就活了。

---

## 二、Loon 明确**不**支持的

| 协议 | 状态 | 替代 |
| --- | --- | --- |
| TUIC | ✗ 无 | 换 Hysteria2，或换客户端（sing-box / Stash） |
| Hysteria v1 | ✗ 只有 v2 | 让机场升级到 v2 |
| Snell | ✗ 无 | Surge 专属，Loon 无计划 |
| WireGuard URI | ✗ 只有标准格式 | 手写 `[Proxy]` 行 |
| naiveproxy / Juicity | ✗ 无 | — |

判断依据：官方单节点文档的协议章节 + 订阅 URI 白名单。
URI 白名单原文：`ss://`、`ssr://`、`vmess://`、`vless://`、`trojan://`、`hysteria2://`、`hy2://`、`anytls://`。

**这条白名单是硬边界。** 机场给了 `tuic://` 节点，Loon 订阅时会被静默丢弃，不是配置错误。

---

## 三、每个协议真正在解决什么问题

按「对抗什么」分组，比按名字排有用。

### 组 1：对抗「流量特征识别」—— 老协议的续命术

**ShadowTLS** 是这一组的核心。SS、SSR、HTTP、SOCKS5、VMess、VLESS 六种协议都能加 ShadowTLS：

```
协议 = Shadowsocks,host,443,aes-128-gcm,"pw",shadow-tls-password="x",shadow-tls-sni=www.example.com,shadow-tls-version=3
```

它把明文协议塞进一次真实的 TLS 握手后面，让被动探测只看到「一个连 www.example.com 的 TLS 连接」。
v3 相比 v2 补了应用数据阶段的特征，v2 现在已不可靠。

**代价**：多一次往返，且 SSL 库指纹要和伪装目标一致，否则 TLS-in-TLS 特征照样暴露 → 这就是组 2 要解决的。

### 组 2：对抗「TLS-in-TLS 检测」—— 当前的主战场

任何「TLS 套 TLS」的方案（Trojan over TLS、VMess over WSS、ShadowTLS 保护的 SS）都有同一个结构特征：**外层 TLS 连接里跑的是另一层 TLS 握手字节**。DPI 不需要解密，看包长分布和握手时序就能判。

三个应对路线：

1. **Reality**（Loon 支持，VMess/VLESS/Trojan 都有）
   不自己造证书，直接借用真实网站的 TLS 握手。服务端持有对应域名的私钥片段，客户端用 `public-key` + `short-id` 验证。
   好处：不需要域名、不需要证书、被动探测拿到的是真实网站的证书链。
   ```
   VLESS = VLESS,host,443,"uuid",transport=tcp,flow=xtls-rprx-vision,public-key="...",short-id=...,over-tls=true,sni=www.example.com,tls-profile=chrome,udp=true
   ```
   `flow=xtls-rprx-vision` 是给 Vision 用的，作用是抹掉 TLS-in-TLS 的包长特征——**Reality 不配 Vision，等于只做了一半**。

2. **AnyTLS**（Loon 已支持）
   不伪装成某个网站，而是用 padding 把包长分布抹平，并用连接复用池让多个流共享一条 TLS 连接，消除「每次请求都新建 TLS」的时序特征。
   ```
   AnyTLS = AnyTLS,host,443,"pw",sni=host,tls-profile=chrome,idle-session-timeout=30,max-stream-count=8,udp=true
   ```
   它也能叠 Reality（`public-key` + `short-id`）。

3. **Hysteria2 + Salamander**
   不走 TLS，走 QUIC，用 Salamander 对 QUIC 载荷做混淆：
   ```
   Hysteria2 = Hysteria2,host,443,"pw",sni=host,salamander-password=obfs,server-ports="20000:20100",hop-interval=30,download-bandwidth=100,udp=true
   ```

### 组 3：对抗「UDP QoS」

运营商对未知 UDP 流量的处理经常是限速或丢包。Hysteria2 的端口跳跃就是为此设计的：

```
server-ports="20000:20100",hop-interval=30
```

客户端每 30 秒换一个服务端端口，让 QoS 策略来不及建立流表。**服务端必须把整段端口都映射进容器/防火墙**，否则跳跃到没开的端口就断。

`download-bandwidth` 单位是 Mbps，填的是「你愿意让服务端按多少带宽发」，填太小会成为瓶颈。

### 组 4：隧道，不是代理

**WireGuard** 在 Loon 里是完整隧道，不是「节点」：

```
WireGuard = WireGuard,interface-ip=192.168.2.2,private-key="...",mtu=1280,dns=192.168.2.1,keepalive=45,peers=[{public-key="...",allowed-ips="0.0.0.0/0,::/0",endpoint=wg.example.com:51820}],udp=true
```

它和分流规则的关系比较特殊：`allowed-ips` 决定哪些流量进隧道，Loon 的规则决定哪些请求走这个节点。两者都满足才生效。
`reserved=[1,2,3]` 是给 Cloudflare WARP 用的，普通自建不用填。

---

## 四、选型矩阵

| 场景 | 首选 | 备选 | 理由 |
| --- | --- | --- | --- |
| 日常网页 / 视频 | VLESS + Vision + Reality | Hysteria2 | 抗检测最强，延迟稳定 |
| 移动网络、丢包严重 | Hysteria2 | TUIC（需换客户端） | QUIC 对丢包不敏感 |
| 游戏、语音 | Hysteria2（`udp=true`） | WireGuard | 只有这两种 UDP 转发靠谱 |
| 老机场、只有 SS | SS + ShadowTLS v3 | — | 别裸奔 SS |
| 需要连内网 / 全隧道 | WireGuard | — | 唯一真正的 L3 隧道 |
| 浏览器指纹敏感的目标站 | AnyTLS | VLESS+Vision | AnyTLS 的 padding 更彻底 |
| 极端审查环境 | Reality 系 | Hysteria2 | Reality 不依赖自有域名 |

一条经验：**`tls-profile` 不配，前面全白做。** 服务端再强，客户端握手是 Go 默认指纹，一样被分类。Loon 提供的是 `chrome147` / `safari-ios-26` 这种带版本号的真实指纹，优先用它们而不是 `default`。

---

## 五、QX 侧的现实

QX 的原生协议集停在 SS / SSR / VMess / VLESS / Trojan / HTTP(S) / SOCKS5。
**Hysteria2、TUIC、AnyTLS 都没有原生支持**，`hysteria2://`、`anytls://` 订阅会被忽略。

这意味着：
- 同一份机场订阅，Loon 能吃到全部节点，QX 只能吃到一部分；
- 想让 QX 用上 Hysteria2，只能靠「服务端同时开 Trojan 端口 + 客户端选 Trojan」，不是转换能解决的——协议不同，转换器变不出来。

这也是这套规则集做成「单源双端」而不是「一份配置通用」的原因：**规则可以共享，协议不能。**

---

## 六、开源实现与许可证

协议规范本身**不受版权约束**——你实现 Hysteria2 不需要 apernet 授权。
被许可约束的是**实现代码**。要嵌进自己的产品时才需要看这一列。

| 协议 | 参考实现 | 许可证 |
| --- | --- | --- |
| Shadowsocks | `shadowsocks-rust` | MIT |
| Shadowsocks | `shadowsocks-libev` | GPL-3.0 |
| ShadowTLS | `ihciah/shadow-tls` | MIT |
| VMess / VLESS / Reality | `XTLS/Xray-core` | MPL-2.0（文件级传染） |
| V2Ray（旧） | `v2fly/v2ray-core` | MIT |
| Trojan | `trojan-gfw/trojan` | GPL-3.0 |
| Hysteria 2 | `apernet/hysteria` | MIT |
| WireGuard | `WireGuard/wireguard-go` | MIT |
| AnyTLS | `anytls/anytls-go` | 以仓库 LICENSE 为准 |
| 全家桶 | `SagerNet/sing-box` | GPL-3.0（含附加条款） |
| 全家桶 | `MetaCubeX/mihomo` | GPL-3.0 |

三条实操结论：

1. 做**闭源产品**：只用 MIT/Apache 系（hysteria、shadowsocks-rust、wireguard-go、shadow-tls）。
2. 做**开源工具**：MPL-2.0（Xray）最舒服，改了哪几个文件就开源哪几个，其余可闭源。
3. 一旦链进 **sing-box / mihomo / trojan / libev**，整个产物必须 GPL-3.0 开源，商用要另谈。

---

## 七、Loon 的杀手锏：`Custom`

Loon 允许用 JS 实现一个协议，这是它的协议列表唯一能自己扩的地方：

```
Custom = Custom,host,443,aes-128-gcm,"pw",script-path=https://example.com/my-proto.js,sni=host,udp=true
```

脚本负责握手与加解密，Loon 负责分流、UDP、TLS 指纹。官方示例是「用 JS 自定义 HTTP 代理」，地址在文档里给了。

这条路的价值：**TUIC 之类的缺口可以自己补**——只要你能用 JS 复刻它的握手。代价是没有 Rust/Go 的性能，且脚本每次握手都要跑一遍 JS。

---

## 八、待验证

- QX 各版本对 VLESS 的支持起点（1.3.0 起，但订阅解析行为按版本有差异，以实测为准）；
- `tls-profile` 的可用取值集合随 Loon 版本更新（`chrome147`、`safari-ios-26` 都是带版本号的新增项）；
- `server-dns`、订阅 `[DNS]` / `[Host]` Section 需要 Loon 3.5.2 (996)+。

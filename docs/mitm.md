# MitM 与 CA 证书

结论先说：**当前这套规则不需要 MitM，配置里默认是关的。**

需要它的只有三种场景：

- 改写 HTTPS 响应体（去 App 内开屏广告、改返回的 JSON）
- 按 URL 路径匹配，`DOMAIN-SUFFIX` 只看域名，看不到 `/api/v2/xxx`
- 跑注入脚本

不做这三件事，开着它只会增加开销和故障面。

---

## 一、开起来只要两步

配置里只改一个开关，证书由 App 管。

**第一步，在 Loon 里装证书。**

Loon 里生成 CA 证书，然后 iOS 上要两步：

1. 装描述文件：「设置 → 通用 → VPN 与设备管理」，点安装，输锁屏密码
2. 信任证书：「设置 → 通用 → 关于本机 → 证书信任设置」，打开那个开关

第二歩最容易漏。只做第一步，所有 HTTPS 会失败。

**第二步，配置里打开开关。**

```ini
[MITM]
enable = true
hostname = example.com, *.example.com
#ca-p12 =
#ca-passphrase =
skip-server-cert-verify = false
```

`ca-p12` 保持注释状态就行。不填时用的是 App 内管理的证书，这是官方示例配置的做法。

---

## 二、配置参数

| 参数 | 说明 |
| --- | --- |
| `enable` | 总开关。`hostname` 有值但 `enable` 不是 true，MitM 不生效 |
| `hostname` | 解密白名单，逗号分隔，支持 `*` `?` 通配，域名前加 `-` 表示排除 |
| `ca-p12` | 可选。想把证书固定进配置分发时才填，内容是 P12 的完整单行 Base64 |
| `ca-passphrase` | 配合 `ca-p12` 的密码 |
| `skip-server-cert-verify` | 保持 `false`，设成 true 等于不校验上游证书 |

`hostname` 的写法有个坑：

```
*.example.com        只匹配子域，不包含 example.com 本身
example.com          只匹配裸域名
example.com, *.example.com   要全覆盖就两个都写
```

`%APPEND%` 前缀表示追加到插件自带的列表而不是覆盖。装了改写类插件时要留着它：

```ini
hostname = %APPEND% example.com, *.example.com
```

---

## 三、边界

**越少越好。** `hostname` 每多一个域名，就多一条被解密的流量。写成 `*` 等于解密全部。

**证书固定会拦你。** 银行、支付类、部分游戏的 API 做了 SSL Pinning，校验证书链。你的 CA 不在它的白名单里，结果是连接直接失败，而不是走 MitM 后正常工作。这类域名不要放进 `hostname`，本套规则里它们在 `10-direct` 层，天然不会进白名单。

**收益递减。** 域名级 `REJECT` 已经吃掉大部分广告 SDK 请求。剩下的在响应体里，要改写 JSON，收益小但故障面大。

**证书会过期。** 过期后所有 MitM 流量失败，表现是某个 App 突然打不开而其他正常，很难联想到证书。重新生成并安装即可。

---

## 四、排障

**开了 enable 但改写不生效**：先查 iOS 第二步的信任开关，再查 `hostname` 是否匹配（`*.a.com` 不含 `a.com`）。

**某个 App 突然连不上，其他正常**：把它从 `hostname` 移除，大概率是证书固定。

**所有 HTTPS 都失败**：证书没信任，或证书过期。

**耗电明显上升**：`hostname` 范围太宽，收窄到实际需要改写的几个域名。

---

## 五、验证链路通不通

`conf/loon.mitm.conf` 是开了 MitM 的版本，`hostname` 里放 `example.com`，并且有一条改写规则把它的请求丢弃。

导入后打开 `https://example.com`：

- 打不开，说明整条链路通了
- 能打开，说明有环没通，按顺序查证书、信任开关、`hostname`、配置是否真的切换过去

验完把 `[Rewrite]` 那行删掉。

没有这条规则的话，你分不清「MitM 工作正常」和「证书装了但没信任」。后者的表现是所有 HTTPS 都失败，和正常工作看起来完全不像，但出问题时你也判断不出是哪一种。

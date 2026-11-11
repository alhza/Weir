# 对比：iKeLee 的 Loon 配置在哪些地方比我的对

对象：[luestr/ProxyResource](https://github.com/luestr/ProxyResource)
许可：**CC BY-NC-SA 4.0**（非商业 + 相同方式共享）——见文末。

读的是 `Tool/Loon/Lcf/zh-CN/` 下的 7 份 `.lcf` 和 `Tool/QuantumultX/Config/` 下的 2 份 `.conf`。

---

## 一、架构拆解

他的策略组是**三层**，我的是扁平一层。

```
第一层  场景          ssid=自动优选, default=..., cellular=..., "家里WiFi"=DIRECT
                        ↓
第二层  业务          select=手动/自动/故障转移/负载均衡
                        ↓
第三层  算法          url-test / fallback / load-balance
                        ↓
        节点集合      [Remote Filter] 用正则从订阅里筛出来
```

我那版只有 `PROXY = select, DIRECT`，等于把三层压成一层，节点管理全靠手选。

### 第一层：`ssid` 类型的策略组

```
香港手动场景=ssid, default=香港手动策略, cellular=香港手动策略, "PHICOMM_5G"=DIRECT
```

**这一条推翻了我上一轮的判断。** 我写过「`ssid-trigger` 只能切模式（DIRECT/PROXY/RULE），切不了配置」——`ssid-trigger` 确实只能切模式，但 `ssid` **类型的策略组**可以按 Wi-Fi 指定任意策略，而且粒度到单个组：香港走代理、日本走代理、家里 Wi-Fi 全直连，互不干扰。

这才是多环境的正确解法。`ssid-trigger` 是全局开关，`ssid` 组是逐组开关，后者细得多。

### [Remote Filter]：用正则代替手选节点

```
香港节点=NameRegex, FilterKey="^(?=.*((?i)🇭🇰|香港|(\b(HK|HKG|Hong)(\d+)?\b)))(?!.*((?i)回国|校园|游戏|🎮|(\b(GAME)\b))).*$"
```

策略组引用的是 `香港节点` 这个集合，不是具体节点名。好处很实在：

- 机场改名、加减节点，配置不用动；
- 集合可以同时被 `select` / `url-test` / `fallback` / `load-balance` 引用，一份定义四处用。

代价是正则要维护，且**依赖机场的命名规范**。他的正则里那串排除词（回国、校园、游戏、群、邀请、返利、官网、客服、流量、到期……）是长期踩坑攒出来的——机场会把「官网地址」「剩余流量」这类信息做成假节点混在订阅里，不排除就会被 url-test 选中。

### [Remote Rule] 的 `tag` 参数

```
https://kelee.one/Tool/Loon/Lsr/AI.lsr, policy=美国手动场景, tag=AI, enabled=true
```

我上一轮从官方 `sub_rule` 文档抄的语法是 `URL,POLICY`，只有两段。实际支持 `policy=` / `tag=` / `enabled=`。

**`tag` 是排障时最有用的东西**：出问题能在 Loon 界面里单独关掉某一组规则，而不是整份配置停用。`enabled=false` 还能把一组规则预置在配置里但不生效。

### `[Plugin]` 段写在配置里

```
https://kelee.one/Tool/Loon/Lpx/BlockAdvertisers.lpx, pin=true, enabled=true
```

插件可以直接列在配置里，`pin=true` 固定在列表顶部。这印证了「插件规则优先级高于订阅规则」——所以插件误杀时，关插件比改规则快。

### `FINAL` 指向策略组

```
FINAL, 兜底后备策略
```

而 `兜底后备策略 = fallback, 香港自动场景, 台湾自动场景, ..., interval=60, max-timeout=2000`。漏网流量按 fallback 逐级降级，而不是死绑 DIRECT 或 PROXY。

---

## 二、我错在哪

| 我上一轮的判断 | 实际 | 影响 |
| --- | --- | --- |
| `ssid-trigger` 只能切模式，多环境得靠多份配置 | `ssid` 类型策略组可逐组按 Wi-Fi 切 | 整个多环境方案要重做 |
| FakeIP 让 IP 层失效，`GEOIP`/`IP-ASN` 是摆设 | Loon 会把假 IP 还原成域名再解析，GEOIP 正常工作 | 我据此推出「FINAL 必须是 DIRECT」，结论错了 |
| 订阅规则语法是 `URL,POLICY` | 支持 `policy=` / `tag=` / `enabled=` | 少了 tag 就没法按组开关 |
| `FINAL,DIRECT` 最安全 | `FINAL` 指向 fallback 组更可控 | 见下 |

第二条最要紧。我当时的推理是「FakeIP → IP 层拿到假地址 → GEOIP 判不准 → 只能靠域名白名单 → 所以 FINAL 必须 DIRECT」。

实际机制是：FakeIP 只负责**截获 App 自发的 DNS 请求并返回假地址**，等请求回来时 Loon 把假 IP **映射回域名**，后续按域名走正常流程、用真实 DNS 解析。`sni-sniffing=true` 还能从 TLS 握手补一道域名还原。所以 IP 层拿到的是真 IP，GEOIP 有效。

一个反证：他这套配置的 `FINAL` 指向代理组，靠 `GEOIP,CN,DIRECT` 兜住国内流量。如果 GEOIP 在 FakeIP 下失效，这套配置会让**所有国内流量绕道海外**——以这个仓库的使用规模，不可能没被发现。

---

## 三、FINAL 该指向哪：两种范式

这不是谁对谁错，是两套前提。

| | 我原来的方案 | 他的方案 |
| --- | --- | --- |
| 默认动作 | `FINAL,DIRECT` | `FINAL,兜底策略组`（→ 代理） |
| 国内判定 | 域名白名单精确列举 | `GEOIP,CN` + 远程地区规则 |
| 前提 | 不需要可信 GEOIP | **需要可信 GEOIP 库** |
| 漏网后果 | 打不开（立刻可见） | 绕道海外（隐形变慢） |
| 维护成本 | 高（要补域名） | 低（地理判定自动覆盖） |
| 薄弱点 | 白名单不全 | GEOIP 库不准 / 地区规则订阅挂掉 |

他敢用「默认代理」是有前提的：`geoip-url=https://geodata.kelee.one/Country-Masaiki.mmdb` 和 `ipasn-url=...` 都是自建库。**用官方内置库做默认代理，风险会大很多。**

### 我改成了折中

```
[Rule]
IP-CIDR, 28.0.0.0/8, DIRECT, no-resolve
IP-CIDR, 198.18.0.0/15, DIRECT, no-resolve
IP-CIDR6, fc00::/7, DIRECT, no-resolve
DOMAIN-SUFFIX,google.com,PROXY     ← 订阅全挂时的保底
...
GEOIP, CN, DIRECT                   ← 写在本地，不依赖远程规则
FINAL, 兜底组                        ← fallback 逐级降级
```

关键改动有两处：

1. **`GEOIP,CN,DIRECT` 放在本地 `[Rule]`，不放远程规则。** 他的版本里这条在 `REGION_SPLITTER.lsr` 里，订阅一挂国内就全绕道；放本地则永远有效。这是把他的思路补上一条失效保护。
2. **`FINAL` 指向 `兜底组 = fallback, 自动优选, 故障转移, DIRECT`。** 比裸写 `PROXY` 多了两级降级，也比裸写 `DIRECT` 更接近「能上网」。

至于那三条 `IP-CIDR ... DIRECT`：`28.0.0.0/8`（美国国防部网段，永远不通）、`198.18.0.0/15`（benchmark 段，也是 FakeIP 用的段）、`fc00::/7`（IPv6 ULA）。这些地址无论如何都到达不了，先直连让它们快速失败，省掉一次代理往返。这是他从实践里攒的，我原来完全没有这一层。

---

## 四、值得抄的五个点

1. **`ssid` 类型策略组**替掉我原本打算的「多份配置文件 + 快捷指令切换」。一份配置就能覆盖家里/公司/蜂窝。
2. **`[Remote Filter]` 正则筛节点**，策略组引用集合而不是节点名。
3. **`[Remote Rule]` 带 `tag=`**，排障时能按组开关，这是最高性价比的一行改动。
4. **`[Plugin]` 段 + `pin=true`**，把插件纳入配置版本管理，而不是在 App 里点。
5. **无效地址前置 DIRECT**（28/8、198.18/15、fc00::/7），让必死连接快速失败。

还有两个我原来没意识到的 `[General]` 键：`geoip-url` 和 `ipasn-url` 可以换地理库——这直接决定了「GEOIP 兜底」这套方案的可靠性上限。

---

## 五、许可证：不能抄内容

仓库是 **CC BY-NC-SA 4.0**：

- **NC**：不得用于商业用途。任何收费产品、付费订阅里的配置都不能用它的内容。
- **SA**：改编作品必须用相同协议发布。把它合并进你的仓库再换 MIT/Apache 发布，不行。

可以做的：**学结构**。段名、参数名、语法、`ssid` 组的写法——这些是软件功能的事实描述，不受版权保护。不能做的：**抄规则内容、抄正则、抄域名列表**。

所以 `conf/loon.conf` 我重写了：保留了它印证过的结构（三层策略组、Remote Filter、Remote Rule 的 tag），正则和规则全部自己写。

---

## 六、还没解决的

- `ipv6-vif`、`dns-reject-mode`、`domain-reject-mode`、`udp-fallback-mode`、`sni-sniffing` 这几个键，官方 `[General]` 文档页里没有，我是按名字推断语义后写进去的，需要按你的 Loon 版本核对；
- QX 侧的 `[dns]` 段支持 `included_ssids` / `excluded_ssids`，**可以按 Wi-Fi 分 DNS**，这是 Loon 没有的能力（Loon 只能用 `[Host]` 里的 `ssid:` 单条映射）。要做双端等价配置，这里是个不对齐点。

# Weir

一份规则源，编译出 Loon 与 Quantumult X 双端分流配置。

按判定链分层：先定动作（拦 / 直连 / 代理），再定出口要求（通用 / 地区 / IP / 稳定）。

---

## 订阅

**Loon**，写在 `[Remote Rule]` 段：

```
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/reject.list, policy=REJECT, tag=去广告, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/direct.list, policy=DIRECT, tag=直连, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy.list, policy=PROXY, tag=代理, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-media.list, policy=流媒体, tag=流媒体, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-ai.list, policy=AI, tag=AI, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-social.list, policy=社交, tag=社交, enabled=true
```

**Quantumult X**，写在 `[filter_remote]` 段：

```
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/reject.list, tag=去广告, force-policy=REJECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/direct.list, tag=直连, force-policy=DIRECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy.list, tag=代理, force-policy=PROXY, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-media.list, tag=流媒体, force-policy=流媒体, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-ai.list, tag=AI, force-policy=AI, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-social.list, tag=社交, force-policy=社交, update-interval=86400, enabled=true
```

顺序就是优先级，别调换。`policy=` 后面的名字必须是你配置里存在的策略组。

完整规范（镜像选择、固定版本、稳定性承诺）见 [docs/referencing.md](docs/referencing.md)。

---

## 结构

```
rules/          规则源，一份
  ├─ 00-reject.list          拦
  ├─ 10-direct.list          直连
  ├─ 20-proxy.list           代理·通用
  ├─ 30-proxy-media.list     代理·地区绑定
  ├─ 40-proxy-ai.list        代理·IP 稳定
  ├─ 50-proxy-social.list    代理·长连接
  └─ 90-direct-ip.list       IP 层兜底

out/            编译产物，两端各六份
conf/           配置骨架，含节点与协议示例
policy.json     策略名映射，换名字改这里
tools/          build.ps1 编译，check-conf.ps1 检查
docs/           设计、引用规范、协议、验证
```

---

## 三条取舍

**默认直连，代理走白名单。** 被墙的主域是有限集合可以穷举，国内长尾域名是无限集合穷举不了。代价是漏网的境外站点直接打不开，好处是故障立刻可见。

**`GEOIP,CN,DIRECT` 写在本地规则，不放远程。** 放远程的话订阅一挂，国内流量全绕道海外，这种失效极难发现。

**本地规则永远赢过订阅。** Loon 的来源优先级是 `本地规则 > 插件规则 > 订阅规则`。所以逃生舱一定有效，插件误杀也能救；但本地规则没法做「晚于订阅生效」的兜底。

---

## 文档

- [design.md](docs/design.md)：判定链、iOS 没有按 App 分流、出口要求决定组类型、FINAL 与失效模式、`[General]` 因果链、节点筛选
- [referencing.md](docs/referencing.md)：**权威来源**，地址、语法、镜像与版本、稳定性承诺。与其他文档冲突时以它为准
- [protocols.md](docs/protocols.md)：Loon 支持哪些代理协议、不支持哪些、各实现的开源许可
- [verify.md](docs/verify.md)：在 iPhone 上导入并逐项验证

---

## 改规则

1. 改 `rules/` 下的文件，或者在 `policy.json` 里换策略组名
2. 跑 `tools/build.ps1` 重新生成 `out/`
3. 跑 `tools/check-conf.ps1` 检查配置有没有断掉的引用
4. 提交 `rules/` 和 `out/`

构建时会自动查五类问题：域名写法（`https://` 前缀、`*.` 星号、前导点这些在 Loon 里永不命中）、重复规则、同一条规则落在两个策略的硬冲突、跨策略遮蔽、QX 不支持的能力降级。

产物全部 LF 行尾。带 `\r` 会让域名尾部多一个字符，而两端解析器都是闭源的。

---

## 已知边界

`raw.githubusercontent.com` 在国内不稳定。订阅依赖它，正好会触发「订阅加载失败」这个失效场景。换 jsDelivr 镜像或把 `out/` 镜像到自己的托管。

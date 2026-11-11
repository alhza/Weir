# Weir

一份规则源，编译出 [Loon](https://nsloon.app) 与 Quantumult X 双端分流配置。

按**失效代价**分层，不按主题分层。默认直连，代理走白名单。

---

## 订阅

### Loon

写在配置的 `[Remote Rule]` 段。`tag` 让你能在界面里单独关掉某一组：

```
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/reject.list, policy=REJECT, tag=去广告, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/direct.list, policy=DIRECT, tag=直连, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy.list, policy=PROXY, tag=代理, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/media.list, policy=流媒体, tag=流媒体, enabled=true
```

### Quantumult X

写在 `[filter_remote]` 段：

```
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/reject.list, tag=去广告, force-policy=REJECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/direct.list, tag=直连, force-policy=DIRECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy.list, tag=代理, force-policy=PROXY, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/media.list, tag=流媒体, force-policy=流媒体, update-interval=86400, enabled=true
```

策略组名 `PROXY` / `流媒体` 必须在你的配置里有定义，改 `policy.json` 可以换成你自己的名字。

---

## 分层

| 层 | 文件 | 默认策略 | 误判后果 |
| --- | --- | --- | --- |
| L0 | `reject.list` | REJECT | 白屏、登录失败、上传中断，**最难排查，可一键关** |
| L1 | `direct.list` | DIRECT | 银行风控、验证码收不到、消息延迟 |
| L3 | `proxy.list` | PROXY | 直接打不开 |
| L4 | `media.list` | 流媒体 | 换区失败 |

REJECT 单独一层是因为它的故障形式最隐蔽。出问题时先关掉这组，再看还坏不坏。

---

## 三条设计取舍

**默认直连，代理走白名单。** 被墙的主域是有限集合，可以穷举；国内长尾域名是无限集合，穷举不了。代价是漏网的境外站点会直接打不开，好处是故障立刻可见。

**`GEOIP,CN,DIRECT` 要写在本地规则，不要放远程。** 放远程的话，订阅一挂国内流量就全绕道海外，这种失效很隐蔽，你可能忍着用一周才发现。

**本地规则永远赢过订阅。** Loon 的规则来源优先级是 `本地规则 > 插件规则 > 订阅规则`。所以：逃生舱一定有效，插件误杀也能靠本地规则救；但本地规则没法做「晚于订阅生效」的兜底。

---

## 改规则

`rules/` 是唯一的规则源，`out/` 是生成产物。

产物由本地构建工具从源生成，构建工具与设计文档不包含在本仓库。改完 `rules/` 之后需要重新生成 `out/` 再提交。

产物全部使用 LF 行尾。带 `\r` 会让规则行的域名尾部多一个字符，而 Loon 与 QX 的解析器都是闭源的，不能赌它会 strip。

---

## 已知边界

raw.githubusercontent.com 在国内访问不稳定。订阅规则依赖它，正好会触发「订阅加载失败」这个失效场景。要么换 jsDelivr 镜像，要么把 `out/` 再发布一份到你自己的托管。

# 文档索引

按性质分四类。要引用这套规则看第一类，要操作看第二类，要查事实看第三类，要理解设计动机看第四类。

## 规范 · 有约束力

**[referencing.md](referencing.md)** 引用规范。

地址、语法、版本与缓存策略、稳定性承诺、换托管要改哪里。其他文档里出现的地址或语法与它冲突时，以它为准。

## 操作指南

**[device-verify.md](device-verify.md)** 在 iPhone 上导入并验证。

导入链接、没有节点时能验证的五项、分流行为的样本点、排障路径。

## 参考 · 事实性

**[protocols.md](protocols.md)** 协议全景。

Loon 支持哪 11 种协议加自定义入口、订阅 URI 白名单的硬边界、不支持 TUIC / Hysteria v1 / Snell、各实现的开源许可。依据是官方文档，官方更新后可能过时，发现落后于文档以官方为准。

## 设计与分析 · 含判断

**[config-design.md](config-design.md)** 配置设计的六个问题。

规则来源优先级为什么让订阅规则永远劣后、FINAL 是失效模式的选择而不是兜底、`[General]` 里五条因果链、跨文件契约只有策略名一处。

**[app-split.md](app-split.md)** 节点筛选与分流策略。

iOS 上没有按 App 分流这回事（进程规则只在 macOS 生效），所以改成按用途分组。含节点筛选的正则设计、排除词清单、以及为什么流媒体和 AI 不能挂自动切换组。

**[peer-review.md](peer-review.md)** 与 iKeLee/ProxyResource 的横向对比。

拆解三层策略组、`ssid` 组、`[Remote Filter]`、`[Remote Rule]` 的 tag，以及我当时判断错的三处（FakeIP 与 GEOIP 的关系、`ssid` 组能切策略、订阅规则语法）。这份文档里有自我修正，读的时候注意区分结论和当时的推理。

---

## 文档之间怎么互指

```
referencing      地址与语法的唯一来源
     ↑
device-verify    照着做的步骤，验证点来自 referencing 的基线数字
     ↑
config-design    解释 conf/ 里每条参数为什么这么写
     ↑
peer-review      解释 config-design 里哪些结论改过、为什么改
```

`protocols.md` 独立，不参与这条链，它是查表用的。

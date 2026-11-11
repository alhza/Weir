# 引用规范

**这份文档是规范。** 其他文档里出现的任何地址、语法、文件名，与本文冲突时以本文为准。

---

## 一、仓库里哪些东西可以被引用

| 路径 | 内容 | 谁引用 | 变化频率 |
| --- | --- | --- | --- |
| `out/loon/*.list` | 编译好的 Loon 规则 | 客户端订阅 | 跟随规则源 |
| `out/qx/*.list` | 编译好的 QX 规则 | 客户端订阅 | 跟随规则源 |
| `conf/loon.conf` | 完整 Loon 配置 | 整份导入 | 低 |
| `conf/qx.conf` | 完整 QX 配置 | 整份导入 | 低 |
| `rules/*.list` | 规则源 | **不直接引用** | 高 |
| `policy.json` | 策略名映射 | **不直接引用** | 低 |

`rules/` 与 `policy.json` 是构建输入。它们不能当订阅用，因为里面没有策略名，客户端会拒。

---

## 二、引用规则（最常用）

### Loon

写在主配置的 `[Remote Rule]` 段。语法是 `URL, policy=策略, tag=显示名, enabled=开关`：

```
[Remote Rule]
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/reject.list, policy=REJECT, tag=去广告, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/direct.list, policy=DIRECT, tag=直连, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy.list, policy=PROXY, tag=代理, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-media.list, policy=流媒体, tag=流媒体, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-ai.list, policy=AI, tag=AI, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/loon/proxy-social.list, policy=社交, tag=社交, enabled=true
```

六行的顺序就是优先级顺序，别调换。`reject` 在前是因为它的误判最难排查。

`policy=` 后面的名字必须是你配置里存在的策略组。用默认值就要有 `PROXY`、`流媒体`、`AI`、`社交` 四个组，改名见 [policy.json](../policy.json)。

`tag=` 不是装饰。出问题时靠它单独关掉一组，比停用整份配置快得多。

### Quantumult X

写在 `[filter_remote]` 段：

```
[filter_remote]
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/reject.list, tag=去广告, force-policy=REJECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/direct.list, tag=直连, force-policy=DIRECT, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy.list, tag=代理, force-policy=PROXY, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-media.list, tag=流媒体, force-policy=流媒体, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-ai.list, tag=AI, force-policy=AI, update-interval=86400, enabled=true
https://raw.githubusercontent.com/alhza/Weir/main/out/qx/proxy-social.list, tag=社交, force-policy=社交, update-interval=86400, enabled=true
```

`force-policy` 会覆盖文件内每行自带的策略，所以两端的规则文件可以共用一套源。

---

## 三、引用整份配置

只在首次搭环境时用。日常更新规则不需要重新导入配置。

### Loon

Loon 提供通用链接，网页里点得动：

```
https://www.nsloon.com/openloon/import?sub=https%3A%2F%2Fraw.githubusercontent.com%2Falhza%2FWeir%2Fmain%2Fconf%2Floon.conf
```

装好 Loon 之后也可以走自定义 scheme，效果一样：

```
loon://import?sub=<URL 编码后的配置地址>
```

配置里的 `[Remote Proxy]` 是空的，导入后必须自己加节点。Loon 会提示没有节点，这是预期状态。

### Quantumult X

QX 没有等价的网页导入入口。用浏览器打开 `conf/qx.conf` 的地址，全选复制，在 QX 的配置编辑器里粘贴覆盖；或者下载成文件后用文件 App 打开。

---

## 四、镜像与版本

同一个文件有三种取法，差别在**延迟**和**可用性**：

| 形式 | 延迟 | 国内可达性 | 适用 |
| --- | --- | --- | --- |
| `raw.githubusercontent.com/alhza/Weir/main/...` | 实时 | 不稳定 | 默认选择 |
| `cdn.jsdelivr.net/gh/alhza/Weir@main/...` | 最长 12 小时 | 较好 | raw 拉不动时 |
| `cdn.jsdelivr.net/gh/alhza/Weir@<commit>/...` | 永久缓存 | 较好 | 复现某天的行为 |
| `gcore.jsdelivr.net/gh/...` | 同 jsDelivr | 较好 | 换节点测速用 |

规则要跟着更新，所以用 `@main`。配置更新频率低，用固定 commit 更稳。

jsDelivr 的 `@main` 有缓存，改了规则不会立刻全网生效。如果需要在几分钟内推到设备，只能走 raw，或者把 `out/` 同步到你自己的托管。

把 `main` 换成 commit 短哈希就能钉死版本：

```
https://cdn.jsdelivr.net/gh/alhza/Weir@a6dd19f/out/loon/proxy.list
```

---

## 五、稳定性承诺

引用方依赖的是路径和格式，所以这两样不能随便动。

**不会变：**

- `out/loon/` 与 `out/qx/` 下的文件名（`reject` / `direct` / `proxy` / `proxy-media` / `proxy-ai` / `proxy-social` 六个 `.list`）
- 文件内每行的格式：`类型,值,策略`，IP 类规则尾部可带 `no-resolve`
- 默认策略名 `REJECT` / `DIRECT` / `PROXY` / `流媒体` / `AI` / `社交`
- 行尾永远是 LF

**会变，且属于正常更新：**

- 规则条数增减。这是日常维护，不需要通知。
- `direct` 和 `proxy` 的具体域名。误判修正会让某个域名换边，行为变化以此为准。

**会变，且属于破坏性变更，会单独发版说明：**

- 文件名增删或重命名
- 策略名调整
- 行格式变化

判断标准一句话：**引用方需要改配置才能继续用，就是破坏性变更。**

---

## 六、换托管

如果你不想依赖 raw，把 `out/` 整个目录镜像到自己的静态托管，然后改两处：

- `policy.json` 里的 `host` 字段
- 重新跑 `tools/build.ps1`，`out/*/_include.conf` 会带上新地址

`conf/` 里的地址是硬编码的，换托管要手动改那几行。这是刻意的：配置文件应该显式写出依赖，而不是藏一层变量。

---

## 七、引用后怎么确认拿到的对

拉一次，数三样：

```
curl -s <proxy.list 地址> | wc -l        行数
curl -s <proxy.list 地址> | head -1      首行是不是 #
curl -s <proxy.list 地址> | grep -c $'\r' 应该是 0
```

当前基线：

| 文件 | 行数（含表头注释） |
| --- | --- |
| `reject.list` | 30 |
| `direct.list` | 51 |
| `proxy.list` | 64 |
| `proxy-media.list` | 23 |
| `proxy-ai.list` | 28 |
| `proxy-social.list` | 31 |

行数对不上不一定是错，规则会增删。但**含 CR 的行必须是 0**，这一条是硬要求：带 `\r` 会让域名尾部多一个字符，而两端解析器都是闭源的。

更完整的设备侧验证流程见 [verify.md](verify.md)。

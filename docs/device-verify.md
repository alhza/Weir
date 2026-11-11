# 在 iPhone 上验证这套配置

目标不是「能不能翻墙」，是**确认 Loon 正确解析了我们生成的规则**。
没有节点也能完成大部分验证，因为规则加载和节点分发是两件独立的事。

---

## 一、导入配置

在 iPhone 的浏览器里点开（会唤起 Loon）：

```
https://www.nsloon.com/openloon/import?sub=https%3A%2F%2Fraw.githubusercontent.com%2Falhza%2FWeir%2Fmain%2Fconf%2Floon.conf
```

如果 raw 拉不动，换 jsDelivr 镜像：

```
https://www.nsloon.com/openloon/import?sub=https%3A%2F%2Fcdn.jsdelivr.net%2Fgh%2Falhza%2FWeir%40main%2Fconf%2Floon.conf
```

这两个是 Loon 官方文档里的「通用链接」形式，把 `loon://` 换成 `https://www.nsloon.com/openloon/`，网页里点得动。装好 Loon 之后也可以直接换成 `loon://import?sub=<编码后的地址>`。

---

## 二、加节点

导入的配置里 `[Remote Proxy]` 是空的，Loon 会提示没有节点。两种补法：

**方式一**：在 Loon 的节点页面添加你自己的机场订阅，然后在 `[Proxy Group]` 里把策略组指向它。当前 `PROXY = select, 场景选择, 自动优选, 故障转移, 香港节点, DIRECT`，其中的 `香港节点` 等名字来自 `[Remote Filter]` 的正则筛选，机场命名规范对不上就筛不出东西，此时靠 `场景选择` 和 `自动优选` 兜住。

**方式二**：直接用 `[Proxy]` 段写一个单节点，最快能验证通路。

`[Remote Proxy]` 的写法：

```
机场A = https://你的订阅地址,parser-enabled=true,udp=default,enabled=true
```

注意写在 `[Remote Proxy]` 段里。写进 `[Proxy]` 是最常见的错，后果是节点一个都加载不出来，而且 Loon 的报错不指向真正原因。

---

## 三、验证：没有节点也能做的五项

**第一项，看配置是否被接受。**
导入后打开配置，如果 Loon 没有弹出语法错误，说明段名和参数名都合法。这一步能抓出 `EXAMPLE_HOST` 之类没替换的占位符、写错的段名（比如把订阅写进 `[Proxy]`）。

**第二项，数六条远程规则。**
`[Remote Rule]` 段应该有六行，tag 分别是「去广告」「直连」「代理」「流媒体」「AI」「社交」。少一行说明某条被 Loon 拒绝了。

**第三项，拉一次订阅。**
点更新订阅，然后看每条规则右侧显示的条数，应该是：

```
reject   30
direct   51
proxy    64
media    23
ai       28
social   31
```

数字对不上，说明远程文件被 CDN 缓存了旧版本，或者拉取失败。这是最快能判断「规则到底有没有到手机上」的指标。

**第四项，看策略组有没有报错。**
`[Proxy Group]` 里六个组如果有一个引用了不存在的成员，Loon 会在策略组页面标红或显示为空。重点看 `场景选择`，它是 `ssid` 类型，少写 `default=` 会让未匹配的 Wi-Fi 下没有可用策略。

**第五项，直接打开 Loon 看有没有「没有可用节点」之外的报错。**
没有节点只会影响代理，不影响分流判断。此时 `PROXY` 里的 `DIRECT` 会兜住，所以国外站点表现为打不开，国内站点正常。

---

## 四、验证：分流行为

开启 Loon 后打开「请求记录」，逐个访问下面几个地址，看命中的规则和策略：

| 访问 | 应命中 | 策略 |
| --- | --- | --- |
| `baidu.com` | `direct.list` 里的 `DOMAIN-SUFFIX,baidu.com` 或走 `GEOIP,CN` | DIRECT |
| `weixin.qq.com` | `direct.list` 的 `weixin.qq.com` | DIRECT |
| `google.com` | `proxy.list` 的 `google.com` | PROXY |
| `github.com` | `proxy.list` 的 `github.com` | PROXY |
| `claude.ai` | `ai.list` 的 `claude.ai` | AI |
| `t.me` | `social.list` 的 `t.me` | 社交 |
| 打开一个有广告的网站 | `reject.list` 里的域名 | REJECT |

`weixin.qq.com` 那条特别值得看：它在 `direct.list` 里，如果被分到 PROXY，说明规则没加载成功，或者本地规则被别的来源盖掉了。

还有一个反直觉的验证点：在 `[Rule]` 段里临时加一条

```
DOMAIN-SUFFIX,example.com,DIRECT
```

然后访问 `example.com`，它应该走直连。因为**本地规则整体优先于订阅规则**，这条不管写在第几行都生效。如果它没生效，说明本地规则段没被正确解析。

---

## 五、排障

**规则拉不到**：换成 jsDelivr 地址试。raw.githubusercontent.com 在国内不稳定，而订阅规则依赖它，正好会触发「订阅加载失败」这个失效场景。

**拉了但条数是 0**：说明文件格式被拒。用浏览器直接打开那个 raw 地址确认能下载，再看首行是不是 `#` 注释，Loon 会跳过注释行。

**分流全走 FINAL**：先关掉去广告那组再试。REJECT 这层的故障表现最隐蔽，白屏、登录失败、上传中断都可能来自它。

**国外站点全打不开，国内正常**：符合预期。当前配置默认直连，代理依赖 `proxy.list` 命中后再走 `PROXY` 策略组，没有节点时就是打不开。

---

## 六、快捷链接

```
打开 Loon        https://www.nsloon.com/openloon/on
关闭 Loon        https://www.nsloon.com/openloon/off
切换分流模式      https://www.nsloon.com/openloon/flowmodel=filter
切换全局直连      https://www.nsloon.com/openloon/flowmodel=direct
更新所有订阅      https://www.nsloon.com/openloon/update?sub=all
```

可以存进 iOS 快捷指令，做成一键切换。

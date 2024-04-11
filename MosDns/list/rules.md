# 域名匹配规则

[规则](https://irine-sistiana.gitbook.io/mosdns-wiki/mosdns-v5/ru-he-pei-zhi-mosdns/yu-ming-pi-pei-gui-ze)

域名规则有多个匹配方式:

- 以 `domain:` 开头，域匹配。e.g: `domain:google.com` 会匹配自身 `google.com`，以及其子域名 `www.google.com`, `maps.l.google.com` 等。
- 以 `full:` 开头，完整匹配。e.g: `full:google.com` 只会匹配自身。
- 以 `keyword:` 开头，关键字匹配。e.g: `keyword:google.com` 会匹配包含这个字段的域名，如 `google.com.hk`, `www.google.com.hk`。
- 以 `regexp:` 开头，正则匹配([Golang 标准](https://github.com/google/re2/wiki/Syntax))。e.g: `regexp:.+\.google\.com$`。

匹配方式可省略。不同插件有不同的默认值。

- domainset 域名表达式省略前缀默认为 domain 域匹配

匹配方式按如下顺序生效: `full` > `domain` > `regexp` > `keyword`。

相同匹配方式的规则按如下顺序生效:

- `domain` 规则: 子域名优先。比如如果同时存在规则 `google.com` 和 `com`。 `www.google.com` 会优先匹配 `google.com`，然后 `com`。(v3.9.0+)
- `regexp` 和 `keyword` 规则生效顺序为规则导入的顺序。

性能:

- `domain` 和 `full` 匹配使用 HashMap，复杂度 O(1)。每 1w 域名约占用 1M 内存。
- `keyword` 和 `regexp` 匹配需遍历，复杂度 O(n)。注意: `regexp` 正则匹配会消耗大量资源。
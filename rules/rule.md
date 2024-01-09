# rules 匹配规则
- DOMAIN-SUFFIX：域名后缀匹配📌
DOMAIN-SUFFIX,youtube.com,policy  将以youtube.com结尾的任何 FQDN 路由到policy，
例如www.youtube.com或foo.bar.youtube.com。这类似于通配符字符+。
- DOMAIN：域名匹配
DOMAIN,www.google.com,policy  仅将www.google.com路由到policy。
- DOMAIN-KEYWORD：域名关键字匹配📌
DOMAIN-KEYWORD,google,policy 将包含google的任何 FQDN 路由到policy，
例如www.google.com或googleapis.com。
- IP-CIDR：IP 段匹配(可以定义内网直连)📌
IP-CIDR,127.0.0.0/8,DIRECT   将任何数据包路由到127.0.0.0/8到DIRECT策略。
IP-CIDR,198.18.0.1/16,REJECT,no-resolve
- SRC-IP-CIDR：源 IP 段匹配
`SRC-IP-CIDR,192.168.1.201/32,DIRECT`   将来自 `192.168.1.201/32` 的任何数据包路由到 `DIRECT` 策略。
- GEOIP：GEOIP 数据库（国家代码）匹配📌
- GEOIP,CN,policy  将任何请求到中国 IP 地址路由到policy。
- DST-PORT：目标端口匹配 (可以限制下载服务器端口)📌
- DST-PORT,80,policy   将任何目标端口为 80 的数据包路由到policy。
- SRC-PORT：源端口匹配
SRC-PORT,80,policy    将来自端口 80 的任何数据包路由到policy。
- PROCESS-NAME：源进程名匹配
PROCESS-NAME,nc,DIRECT   将进程nc路由到DIRECT（支持 macOS、Linux、FreeBSD 和 Windows）。
- RULE-SET：Rule Provider 规则匹配
RULE-SET,Netflix,Netflix  将Netflix规则提供列表(对应rule-providers)路由到Netflix节点
- MATCH：全匹配
- DIRECT：直接连接到目标，没有代理涉及
- REJECT：用于数据包的黑洞。Clash 不会将任何 I/O 处理到这个策略。
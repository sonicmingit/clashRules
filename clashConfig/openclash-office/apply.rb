#!/usr/bin/env ruby
# 仅依赖 Ruby 的 YAML 库，兼容精简版 OpenWrt Ruby 环境。
require 'yaml'
# 校验 IPv4；cidr 为 true 时允许附带 /0～/32 网段前缀。
def valid_ipv4(value, cidr = false)
  raise 'IPv4 address must be text' unless value.is_a?(String)
  address, mask, extra = value.split('/', -1)
  parts = address.split('.', -1)
  raise "Invalid IPv4: #{value}" unless parts.size == 4 && parts.all? { |v| v.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && v.to_i <= 255 }
  raise "Invalid prefix: #{value}" if extra || (mask && (!cidr || !mask.match?(/\A[0-9]{1,2}\z/) || mask.to_i > 32))
end

# 安全读取用户维护的清单，拒绝 YAML 对象反序列化和别名。
# 修改任何配置前，先校验 DNS、出口、域名、网段和固定 hosts。
def load_office(path)
  raw = YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  o = raw.fetch('office')
  raise 'office must be a mapping' unless o.is_a?(Hash)
  valid_ipv4(o.fetch('dns'))
  raise 'DNS must be a single IP' if o['dns'].include?('/')
  raise 'outbound must be DIRECT' unless o.fetch('outbound') == 'DIRECT'
  %w[domain_suffixes networks].each { |k| raise "#{k} must be an array" unless o[k].is_a?(Array) }
  o['domain_suffixes'].each do |v|
    raise "Invalid domain: #{v}" unless v.is_a?(String) && v.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/) && !v.include?('..')
  end
  o['networks'].each { |v| valid_ipv4(v, true) }
  raise 'hosts must be a mapping' unless o.fetch('hosts', {}).is_a?(Hash)
  o.fetch('hosts', {}).each do |host, ip|
    raise 'Invalid hosts name' unless host.match?(/\A[a-zA-Z0-9.-]+\z/)
    valid_ipv4(ip)
  end
  o
end

# 在目标文件同目录写入临时文件，再原子替换，避免写到一半损坏配置。
# 保留原权限；失败时清理本次产生的临时文件。
def atomic_yaml(path, data)
  temp = path + '.office-' + Process.pid.to_s
  begin
    File.open(temp, 'w', File.stat(path).mode & 0777) do |f|
      f.write(YAML.dump(data)); f.flush; f.fsync
    end
    File.rename(temp, path)
  ensure
    File.unlink(temp) if File.exist?(temp)
  end
end

begin
  # 参数：操作类型、office.yaml 路径、OpenClash 生成的配置路径。
  action, source, target = ARGV
  office = load_office(source)
  case action
  # 仅校验，不写入文件。
  when 'validate'
    puts 'office.yaml valid'
  # 输出去重后的小写后缀列表，供 Shell 脚本维护重绑定例外。
  when 'domains'
    puts office['domain_suffixes'].map(&:downcase).uniq
  # 合并到 OpenClash 本次生成的配置，保留其他 DNS 和代理规则。
  when 'apply'
    raise 'Missing Clash config path' unless target && File.file?(target)
    c = YAML.load_file(target)
    raise 'Clash config must be a mapping' unless c.is_a?(Hash)
    dns = c['dns'] ||= {}
    policy = dns['nameserver-policy'] ||= {}
    filters = dns['fake-ip-filter'] ||= []
    # 此处把公司域名加入 Fake-IP 排除列表，仅支持默认 blacklist 模式。
    # whitelist 模式含义相反，直接报错，避免错误放大过滤范围。
    raise 'fake-ip-filter-mode whitelist is unsupported' if dns['fake-ip-filter-mode'] == 'whitelist'
    rules = []
    # 每个后缀同时生成公司 DNS、真实 IP 解析和直连规则。
    # DNS 后的 #DIRECT 指定查询公司 DNS 时使用直连出口。
    office['domain_suffixes'].map(&:downcase).uniq.each do |domain|
      policy['+.' + domain] = ['udp://' + (office['dns'].include?(':') ? '[' + office['dns'] + ']' : office['dns']) + '#DIRECT']
      filters << '+.' + domain unless filters.include?('+.' + domain)
      rules << 'DOMAIN-SUFFIX,' + domain + ',DIRECT'
    end
    # 直连连接的域名解析也遵循公司域名的专用 DNS 策略。
    dns['direct-nameserver-follow-policy'] = true
    # IP 规则不触发额外 DNS 查询，适合直接访问公司 IP 的应用。
    office['networks'].uniq.each do |cidr|
      kind = 'IP-CIDR'
      rules << "#{kind},#{cidr},DIRECT,no-resolve"
    end
    # 可选固定 hosts 覆盖同名记录；默认空映射不增加绑定。
    c['hosts'] = (c['hosts'] || {}).merge(office.fetch('hosts', {}))
    # 公司规则置顶；移除完全相同的旧规则，避免重复合并产生重复项。
    c['rules'] = rules + (c['rules'] || []).reject { |r| rules.include?(r) }
    atomic_yaml(target, c)
  else
    raise 'Usage: apply.rb validate|domains|apply office.yaml [generated-clash.yaml]'
  end
# 校验或写入失败时返回非零状态，让调用脚本停止后续操作。
rescue StandardError => e
  warn "Office config error: #{e.message}"
  exit 1
end

#!/bin/sh
# OpenClash 覆写入口：第一个参数是本次生成的 Clash 配置文件路径。
# 每次启动或重新生成配置时调用，将公司清单合并进去。
# 合并失败即返回错误，不静默忽略无效清单。
set -eu
BASE=/etc/openclash/custom/office
# 读取固定位置的清单，只修改传入的生成配置，不修改订阅源文件。
ruby "$BASE/apply.rb" apply "$BASE/office.yaml" "$1"

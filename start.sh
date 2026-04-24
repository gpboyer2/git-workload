#!/usr/bin/env bash

# 制品解压后的固定启动入口。
# 用户要求双击或直接执行 start.sh 时只启动内置脚本，不绕到 npm、GitHub Pages、Vercel 或其他旧入口。
# 实际统计逻辑统一收敛在 ./bin/git-workload-report.sh，避免两个启动入口产生两套行为。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$script_dir/bin/git-workload-report.sh" "$@"

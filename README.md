# git-workload-report

`git-workload-report` 是一个面向中文团队的本地 Git 工作量统计工具。它读取本机 Git 仓库历史，生成本地 CSV 报告、TXT 报告或本机 Web 报告页，用于查看指定时间范围内的提交次数、新增/删除代码行、开发者分布、仓库分布、提交时间分布，以及加班、提交类型、文件所有权等深度指标。

当前版本：**1.0.9**

## 重要：本仓库包含两套运行引擎

这个仓库现在同时有两套东西，请先分清，避免用错入口：

| 引擎 | 入口 | 形态 | 状态 | 说明 |
|------|------|------|------|------|
| **本地报告引擎（已发布）** | `start.sh` → `bin/git-workload-report.sh`（内嵌 Python） | 解压即用，产物见 `git-workload-report-v*.tar.gz` | 稳定 | 产出 CSV / TXT / 本地 Web 报告页，是本工具对外发布的主形态 |
| **TypeScript CLI（开发中）** | `node dist/index.js`（源码在 `src/`，编译产物 `dist/`） | npm 包 / Node 进程 | 开发中 | 更丰富的终端分析（单仓库 / 多仓库、996 指数、加班、时区、节假日调休等），尚未接入 npm `bin` |

两套引擎共用同一批 Git 仓库数据，但**输出形态不同**：本地报告引擎走 CSV / TXT / Web；TypeScript CLI 走彩色终端表格。

---

## 快速开始

### A. 最终用户：下载制品直接用（推荐）

1. 从 GitHub Releases 下载 `git-workload-report-v*.tar.gz` 并解压。
2. 编辑解压目录里的 `directory.txt`，每行写一个要统计的 Git 仓库路径（支持 `#` 注释、空行忽略）。
3. 运行：

```bash
# 导出 CSV 到当前目录
./start.sh

# 打开本机 Web 报告页（localhost）
./start.sh web
```

默认统计近 7 天。`directory.txt` 不存在且未传仓库路径时，脚本会从所在目录向上找 Git 仓库。

### B. 开发者：从源码运行

```bash
# 1. 安装依赖（Node >= 16）
npm install

# 2. 编译 TypeScript（产出 dist/）
npm run compile

# 3. 运行 TypeScript CLI（终端分析）
npm run preview -- [仓库路径...] [选项]
# 等价于： node dist/index.js [仓库路径...] [选项]

# 4. 运行/调试本地报告引擎（Python 引擎，localhost Web 见下节）
npm run dev
```

---

## 启动本地报告页（localhost / Web 模式）

本地 Web 报告页由**本地报告引擎**生成，全部数据在本机处理，不依赖任何公网服务。三种启动方式：

```bash
# 方式 1：制品入口，编辑好 directory.txt 后
./start.sh web

# 方式 2：指定仓库清单 + 自定义端口（开发调试常用）
GIT_WORKLOAD_REPORT_PORT=21960 ./start.sh directory=./directory.txt web

# 方式 3：源码仓库里直接跑 Python 引擎并开启 Web（KEEP_ALIVE 保持进程便于调试）
GIT_WORKLOAD_REPORT_KEEP_ALIVE=1 ./bin/git-workload-report.sh web
```

- 默认服务地址：`http://127.0.0.1:19960`
- 端口被占用时会自动向后查找（19960 → 19961 → …），日志里会打印最终地址。
- 脚本会自动尝试用系统默认浏览器打开；若当前环境无可用打开命令（如部分 WSL / 服务器），**不会报错退出**，只打印本地地址，手动复制访问即可。
- 统计过程持续输出 `[进度]` 日志。仓库较大、历史较多或 WSL 读 Windows 盘目录时，只要终端仍在输出进度，就表示程序在运行。
- Web 模式默认展示近 7 天，但后台会按更大数据范围（默认 `2022-01-01` 起）生成 `report-data.json`，便于页面切换"全部时间 / 近 30 天 / 今年"等范围继续筛选。

> 注意：TypeScript CLI（`npm run preview`）是**纯终端**工具，不开启 Web 服务。要看可视化报告页请用上面的本地报告引擎（`web`）。

---

## 本地报告引擎：命令行参数

解压制品或源码根目录执行：

```bash
./start.sh [参数...]
./start.sh [开始日期] [结束日期] [作者关键词] [仓库路径...]
./start.sh web [开始日期] [结束日期] [作者关键词] [仓库路径...]
./start.sh directory=/path/to/directory.txt [web] [开始日期] [结束日期] [作者关键词]
```

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `web` | 否 | 终端模式 | 启动本机 Web 报告页（localhost） |
| `开始日期` | 否 | 近 7 天开始 | Git log 起始日期，格式 `YYYY-MM-DD` |
| `结束日期` | 否 | 当前日期 | Git log 结束日期，格式 `YYYY-MM-DD` |
| `作者关键词` | 否 | 空 | 传给 `git log --author` 的作者过滤关键词 |
| `仓库路径...` | 否 | 脚本所在 Git 仓库 | 一个或多个本地 Git 仓库路径 |
| `directory=/path/to/file.txt` | 否 | `./directory.txt` | 仓库路径清单文件，每行一个 Git 仓库路径 |
| `config=/path/to/config.json` | 否 | `./config.json` | 运行配置文件，当前可配置 GitLab API 地址 |

说明：
- `directory` 表示"仓库路径清单配置文件"，不是仓库目录；文件名可自定义，但后缀必须是 `.txt`。
- 不传 `directory` 时，默认读取制品/仓库根目录的 `directory.txt`；该文件不存在且未传仓库路径时，才从脚本所在目录向上查找 Git 仓库根目录。
- 作者关键词只作为启动默认筛选，页面打开后仍可多选仓库、人员并调整时间段。
- 本引擎依赖 `python3`，缺失会直接报错退出。

---

## TypeScript CLI：命令行参数

通过 `npm run preview -- [参数]` 或 `node dist/index.js [参数]` 运行。CLI 会**智能判断**单仓库 / 多仓库模式：

```bash
# 单仓库：分析当前仓库（默认回溯最近一年）
node dist/index.js
node dist/index.js /path/to/repo
node dist/index.js -y 2025                 # 分析 2025 整年
node dist/index.js --self                   # 只统计当前 Git 用户
node dist/index.js --ignore-author "bot"    # 排除机器人提交

# 多仓库：传入多个路径，或在一个含多个子仓库的目录运行
node dist/index.js /proj1 /proj2
node dist/index.js /workspace
```

常用选项：

| 选项 | 说明 |
|------|------|
| `-s, --since <date>` | 开始日期 `YYYY-MM-DD` |
| `-u, --until <date>` | 结束日期 `YYYY-MM-DD` |
| `-y, --year <year>` | 年份或年份范围，如 `2025` 或 `2023-2025` |
| `--all-time` | 分析整个仓库历史（默认最近一年） |
| `--self` | 仅统计当前 Git 用户的提交 |
| `-H, --hours <range>` | 手动指定标准工作时间，如 `9-18` 或 `9.5-18.5` |
| `--half-hour` | 以半小时粒度展示时间分布（默认按小时） |
| `--ignore-author <regex>` | 排除匹配的作者，如 `bot\|jenkins` |
| `--ignore-msg <regex>` | 排除匹配的提交消息，如 `merge\|lint` |
| `--timezone <offset>` | 指定时区分析，如 `+0800` |
| `--cn` | 强制开启中国节假日调休模式 |
| `--skip-user-analysis` | 跳过团队工作模式分析 |
| `--max-users <number>` | 最大分析用户数（默认 30） |

---

## directory.txt 格式

每行一个 Git 仓库路径；空行与 `#` 开头的注释行忽略；后缀必须是 `.txt`。

```text
# 每行填写一个需要统计的 Git 仓库路径
/Users/peng/Desktop/Project/codex-config
/Users/peng/Desktop/Project/git-workload
/Users/peng/Desktop/Project/pre-commit-hooks
```

---

## config.json 格式

仓库根目录可放一个 `config.json`，用于指定 GitLab API 根地址：

```json
{
  "gitlab_api_base_url": "http://192.168.31.99:8929/gitlab"
}
```

规则：
- `gitlab_api_base_url` 显式指定 GitLab API 根地址；配置了就优先用，否则回退到自动识别（结合远程 URL、常见端口猜地址）。
- 也可用 `config=/path/to/config.json` 指定其他配置文件。

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GIT_WORKLOAD_REPORT_PORT` | `19960` | Web 模式本地服务起始端口，被占用时自动向后查找 |
| `GIT_WORKLOAD_REPORT_KEEP_ALIVE` | 空 | 值为 `1` 时保持本地服务进程（用于开发调试） |

---

## 输出结构

### 默认导出（CSV）

不带 `web` 执行时，脚本先输出统计进度日志，然后直接在当前执行目录导出一个 CSV：

- 文件名格式：`output_YYYYMMDDHHmm.csv`
- 内容分两段：项目维度、人员维度；文件头写入统计开始/结束时间。

### Web 输出（localhost）

Web 模式启动 `127.0.0.1` 本地服务并打开报告页。页面数据来源是脚本生成的 `report-data.json`。支持：

- 仓库复选框筛选（首次默认全选）
- 开发者复选框筛选（跟随时间段与仓库筛选动态刷新）
- 时间段筛选（近 7 天 / 近 30 天 / 今年 / 全部时间）
- 图表展示、CSV 导出、TXT 导出
- 页面筛选与 TXT 导出必须基于当前筛选后的 commits，与页面展示一致

### TXT 导出格式

使用当前页面筛选后的数据，包含：生成/导出时间、当前时间范围、仓库筛选、开发者筛选、核心汇总、仓库数量、有提交项目数、仓库信息、项目提交占比、开发者工作量、一周七天分布、24 小时分布等。

文件名格式：`git-workload-report-开始日期_结束日期.txt`

### report-data.json 数据格式（节选）

Web 页面与导出都读这份本机生成的文件，结构如下（节选关键字段）：

```json
{
  "generated_at": "2026-04-24T15:34:13",
  "default_filter": {
    "start_date": "2026-04-01",
    "end_date": "2026-04-24",
    "author_keyword": ""
  },
  "data_range": { "start_date": "2022-01-01", "end_date": "2026-04-24" },
  "projects": ["ppll-server", "ppll-wap"],
  "active_projects": ["ppll-server"],
  "authors": ["Raymond", "hh"],
  "repos": [
    { "name": "ppll-server", "branch": "dev", "path": "/Users/peng/Desktop/Project/0-ppll/ppll-server" }
  ],
  "commits": [
    {
      "project": "ppll-server",
      "project_path": "/Users/peng/Desktop/Project/0-ppll/ppll-server",
      "hash": "完整 commit hash",
      "short_hash": "短 hash",
      "author": "Raymond",
      "email": "author@example.com",
      "time": "2026-04-24T10:30:00+08:00",
      "date": "2026-04-24",
      "hour": "10",
      "week_day": "5",
      "subject": "提交说明",
      "added": 10,
      "deleted": 2,
      "files": [{ "file": "src/index.js", "added": 10, "deleted": 2 }]
    }
  ],
  "errors": [{ "project": "repo-name", "message": "读取失败原因" }]
}
```

---

## 统计指标与公式

本地报告引擎的部分核心指标：

```text
日均提交次数      = 提交次数 / 统计天数
单日工作时长估算  = 当天最晚提交小时 - 当天最早提交小时 + 1
日均工作时长      = 总估算工作时长 / 有提交的天数
每周工作时长      = 日均工作时长 * 5
加班时间占比      = max(每周工作时长 - 40, 0) / 每周工作时长 * 100
```

TypeScript CLI 还额外计算：996 指数、加班/周末/深夜比例、跨时区协作检测、中国节假日调休判断、提交类型（Conventional Commits）细分、文件所有权与知识孤岛、贡献集中度（基尼系数 / Bus Factor / 帕累托）等，详见终端输出。

---

## 项目结构（源码）

```text
git-workload/
├── bin/
│   └── git-workload-report.sh      # 本地报告引擎入口（内嵌 Python，CSV/TXT/Web）
├── start.sh                        # 制品固定启动入口，转发给 bin/
├── directory.txt                   # 默认仓库清单（每行一个仓库路径）
├── config.json                     # 运行配置（GitLab API 地址等）
├── public/
│   └── local-report/               # 本地 Web 报告页（index.html / app.js / styles.css / chart.umd.js）
├── src/                            # TypeScript CLI 源码（开发中）
│   ├── cli/                        # 命令注册、参数解析、报表打印
│   ├── core/                       # 计算算法（996 指数、加班、时区、项目分类）
│   ├── git/                        # Git 数据采集与合并
│   ├── workspace/                  # 多仓库扫描
│   ├── utils/                      # 终端/格式化/节假日/版本等工具
│   └── index.ts                    # CLI 入口
├── dist/                           # TypeScript 编译产物（npm run compile 生成）
├── scripts/
│   ├── build-release.sh            # 本地构建 tar.gz 制品
│   └── build-github.sh             # 自增版本号 + 打 tag + 推送触发 GitHub Actions
├── .github/workflows/release.yml   # 推送 v* tag 自动构建并发布 Release
└── package.json
```

---

## 开发与构建脚本

| 脚本 | 作用 |
|------|------|
| `npm install` | 安装依赖（Node >= 16） |
| `npm run compile` | `tsc` 编译 `src/` → `dist/` |
| `npm run dev` | 编译后运行本地报告引擎，并 `KEEP_ALIVE=1` 保持进程便于调试 |
| `npm run preview` | 运行 TypeScript CLI（`node dist/index.js`） |
| `npm test` | Jest 单元测试 |
| `npm run build-local` | 构建本地 tar.gz 制品到 `release/` |
| `npm run build-github` | 自增补丁版本号、提交、`git tag` 并推送，触发 GitHub Actions 发布 |

本地验证（开发完成后建议执行）：

```bash
npm run compile
npm test
npm run build-local
tar -tzf git-workload-report-v1.0.9.tar.gz
```

制品内需至少包含：

```text
git-workload-report/start.sh
git-workload-report/directory.txt
git-workload-report/bin/git-workload-report.sh
git-workload-report/public/local-report/index.html
git-workload-report/public/local-report/app.js
git-workload-report/public/local-report/styles.css
git-workload-report/README.md
git-workload-report/LICENSE
```

---

## 发布流程

推送 `v*` 格式的 tag 会自动触发 `.github/workflows/release.yml`：

1. `npm run build-github` 会检查工作区是否干净，自增补丁版本号（如 `1.0.9` → `1.0.10`），修改 `package.json` / `package-lock.json`，打 `vX.Y.Z` tag 并推送。
2. GitHub Actions 收到 tag 后：`npm ci` → `npm run build-local` 构建 tar.gz → `npm test`（失败不阻断）→ 用 commit log 生成 Release 说明并附上制品。

本地手动发布：

```bash
npm run build-github          # 自动 bump + tag + push，触发 Actions
# 或指定版本：
VERSION=1.0.10 npm run build-github
```

---

## 约束与维护说明

- 所有数据只在本机处理，不上传外网；打包产物必须内置报告页，不依赖 GitHub Pages / Vercel 等公网服务。
- 禁止把页面入口改回外网地址；禁止让 `start.sh` 绕过 `./bin/git-workload-report.sh`。
- 页面筛选与 TXT 导出必须基于当前筛选后的 commits，不能导出全量原始数据。
- 统计过程必须持续输出 `[进度]` 日志，避免慢设备 / WSL / 大仓库场景下用户误以为卡死。
- 修改脚本参数时同步更新本文档输入结构；修改 `report-data.json` 字段时同步更新本文档输出结构与页面读取逻辑；修改打包逻辑时确认 `start.sh`、`directory.txt`、`bin`、`public/local-report` 都进入制品。
- 注释只写业务目的、关键约束和公式来源，不解释普通赋值、循环和 DOM 操作。

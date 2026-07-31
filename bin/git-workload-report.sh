#!/usr/bin/env bash

# 本脚本的业务目的必须保持清晰：给中文用户统计 Git 项目工作量。
# 禁止把报告入口改回 GitHub Pages、Vercel 或任何外网地址；打包后的产物必须不依赖公网服务。
# 项目已经从原始加班分析场景改为通用 Git 工作量统计场景，入口命名只使用 git-workload-report。
# 本脚本启动时会生成本地 report-data.json，终端报告和页面必须基于这份本地数据展示。
# 用户这次明确要求 directory 参数指向一个用户自定义名称的 .txt 配置文件。
# 这里的 directory 不是仓库目录，而是“仓库目录清单文件”；禁止改成自动猜测目录或兼容其他后缀。
# 制品根目录必须内置 directory.txt；用户不传 directory 参数时，默认读取这个文件。
# 配置文件每行写一个 Git 仓库路径，空行和 # 开头的注释行会被忽略。

Help()
{
   echo "你可以使用自定义参数进行指定查询"
   echo
   echo "格式:"
   echo "  ./start.sh [开始日期] [结束日期] [作者关键词] [仓库路径...]"
   echo "  ./start.sh web [开始日期] [结束日期] [作者关键词] [仓库路径...]"
   echo "  ./start.sh directory=/path/to/directory.txt [web] [开始日期] [结束日期] [作者关键词]"
   echo "示例: ./start.sh 2026-04-01 2026-04-24 peng /path/to/project-a /path/to/project-b"
   echo "示例: ./start.sh directory=./directory.txt web"
   echo "说明:"
   echo "  默认导出最近 7 天的 CSV 报告到当前目录。"
   echo "  使用 web 子命令时启动本机 localhost 可视化报告页。"
   echo "  directory 参数必须指向 .txt 配置文件，文件名可自定义，后缀必须是 txt。"
   echo "  不传 directory 参数时，默认读取制品根目录的 directory.txt。"
   echo "  directory 配置文件每行写一个 Git 仓库路径，空行和 # 开头的注释行会被忽略。"
   echo "  directory.txt 不存在且不传仓库路径时，才从脚本所在目录向上查找 Git 仓库根目录。"
   echo "  作者关键词只作为启动时默认筛选，页面打开后仍可多选项目、人员并调整时间段。"
   echo
}

if [ "$1" == "--help" ] || [ "$1" == "-h" ]
then
    Help
    exit 0
fi

report_mode="terminal"
directory_config_path=""
app_config_path=""
business_args=()
time_start_provided="0"
time_end_provided="0"

for arg in "$@"
do
    case "$arg" in
    web)
        report_mode="web"
        ;;
    directory=*)
        directory_config_path="${arg#directory=}"
        ;;
    config=*)
        app_config_path="${arg#config=}"
        ;;
    *)
        business_args+=("$arg")
        ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1
then
    echo "未找到 python3，无法生成 Git 工作量报告。"
    echo "请先安装 python3 后重新运行。"
    exit 1
fi

open_local_url()
{
    local target_url="$1"

    if [ -r /proc/version ] && grep -qi microsoft /proc/version
    then
        if command -v cmd.exe >/dev/null 2>&1
        then
            cmd.exe /C start "" "$target_url" >/dev/null 2>&1 && return 0
        fi

        if command -v powershell.exe >/dev/null 2>&1
        then
            powershell.exe -NoProfile -Command "Start-Process '$target_url'" >/dev/null 2>&1 && return 0
        fi
    fi

    if command -v open >/dev/null 2>&1
    then
        open "$target_url" >/dev/null 2>&1 && return 0
    fi

    if command -v xdg-open >/dev/null 2>&1
    then
        xdg-open "$target_url" >/dev/null 2>&1 && return 0
    fi

    if command -v wslview >/dev/null 2>&1
    then
        wslview "$target_url" >/dev/null 2>&1 && return 0
    fi

    return 1
}

script_path=`python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}"`
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
default_directory_config_path="$script_dir/../directory.txt"
default_app_config_path="$script_dir/../config.json"
source_web_dir="$(cd "$script_dir/../public/local-report" && pwd)"

if [ -z "$directory_config_path" ] && [ -f "$default_directory_config_path" ]
then
    directory_config_path="$default_directory_config_path"
fi

if [ -z "$app_config_path" ] && [ -f "$default_app_config_path" ]
then
    app_config_path="$default_app_config_path"
fi

if [ -n "$directory_config_path" ]
then
    case "$directory_config_path" in
    *.txt)
        ;;
    *)
        echo "directory 参数必须指向 txt 配置文件，例如：directory=/path/to/directory.txt"
        exit 1
        ;;
    esac

    if [ ! -f "$directory_config_path" ]
    then
        echo "directory 配置文件不存在：$directory_config_path"
        exit 1
    fi
fi

if [ -n "$app_config_path" ]
then
    case "$app_config_path" in
    *.json)
        ;;
    *)
        echo "config 配置文件必须是 .json 格式：$app_config_path"
        exit 1
        ;;
    esac

    if [ ! -f "$app_config_path" ]
    then
        echo "config 配置文件不存在：$app_config_path"
        exit 1
    fi
fi

time_start="${business_args[0]}"
time_end="${business_args[1]}"
author="${business_args[2]}"

if [ -n "$time_start" ]
then
    time_start_provided="1"
fi

if [ -n "$time_end" ]
then
    time_end_provided="1"
fi

if [ -z "$time_start" ]
then
    # GNU date 用 -d，BSD/macOS date 用 -v，都失败时回退 python3 计算，保证三端可用
    time_start=$(date -d "$(date "+%Y-%m-%d") -6 day" "+%Y-%m-%d" 2>/dev/null || date -v-6d "+%Y-%m-%d" 2>/dev/null || python3 -c 'from datetime import date, timedelta; print(date.today() - timedelta(days=6))')
fi

if [ -z "$time_end" ]
then
    time_end=$(date "+%Y-%m-%d")
fi

if [ -z "$author" ]
then
    author=""
fi

default_filter_start="$time_start"
default_filter_end="$time_end"
collect_time_start="$time_start"
collect_time_end="$time_end"

if [ "$report_mode" = "web" ] && [ "$time_start_provided" = "0" ]
then
    collect_time_start="2022-01-01"
fi

repo_args=()
business_arg_count=${#business_args[@]}
business_index=3
while [ "$business_index" -lt "$business_arg_count" ]
do
    repo_args+=("${business_args[$business_index]}")
    business_index=$((business_index + 1))
done

work_dir=`mktemp -d /tmp/git-workload-report.XXXXXX`
if [ "$report_mode" = "web" ]
then
    cp -R "$source_web_dir"/. "$work_dir"/
fi

python3 - "$report_mode" "$collect_time_start" "$collect_time_end" "$default_filter_start" "$default_filter_end" "$author" "$script_dir" "$work_dir/report-data.json" "$directory_config_path" "$app_config_path" "${repo_args[@]}" <<'PY'
import csv
import json
import os
import re
import ssl
import subprocess
import sys
import zipfile
from urllib import error, parse, request
from datetime import datetime

report_mode, collect_time_start, collect_time_end, default_filter_start, default_filter_end, author_filter, default_dir, output_path, directory_config_path, app_config_path, *input_paths = sys.argv[1:]

def load_app_config(path):
    if not path:
        return {}
    try:
        with open(path, "r", encoding="utf-8") as file:
            data = json.load(file)
    except Exception as exc:
        raise SystemExit(f"config 配置文件读取失败：{path}，{exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"config 配置文件格式错误：{path}，根节点必须是 JSON 对象")
    return data

app_config = load_app_config(app_config_path)

def print_progress(message):
    print(f"[进度] {message}", flush=True)

def run_git(repo_path, args):
    # -c core.quotepath=false：避免中文文件名被转义成八进制（"\346..."）
    return subprocess.check_output(["git", "-C", repo_path, "-c", "core.quotepath=false", *args], text=True, stderr=subprocess.DEVNULL)

def is_git_repo(path):
    try:
        run_git(path, ["rev-parse", "--is-inside-work-tree"])
        return True
    except Exception:
        return False

def git_root(path):
    return os.path.realpath(run_git(path, ["rev-parse", "--show-toplevel"]).strip())

def git_branch(path):
    return run_git(path, ["rev-parse", "--abbrev-ref", "HEAD"]).strip()

def git_remote_url(path):
    try:
        return run_git(path, ["remote", "get-url", "origin"]).strip()
    except Exception:
        return ""

def ssh_host_info(alias):
    try:
        result = subprocess.run(
            ["ssh", "-G", alias],
            text=True,
            capture_output=True,
            check=True,
        )
    except Exception:
        return {"hostname": alias, "port": ""}
    values = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            values[parts[0].lower()] = parts[1].strip()
    return {
        "hostname": values.get("hostname", alias),
        "port": values.get("port", ""),
    }

def guess_gitlab_base_url(repo_path, project_path):
    if not repo_path or not project_path:
        return ""
    head_log_path = os.path.join(repo_path, ".git", "logs", "HEAD")
    if not os.path.exists(head_log_path):
        return ""
    try:
        with open(head_log_path, "r", encoding="utf-8", errors="ignore") as file:
            lines = file.readlines()
    except Exception:
        return ""
    suffix = f"/{project_path}.git"
    for line in reversed(lines):
        marker = "clone: from "
        if marker not in line:
            continue
        candidate = line.split(marker, 1)[1].strip()
        if candidate.endswith(suffix):
            return candidate[: -len(suffix)]
    return ""

def parse_remote_info(remote_url, repo_path=""):
    if not remote_url:
        return {"provider": "unknown", "remote_url": remote_url}
    value = remote_url.strip()
    ssh_port = ""
    if value.startswith("git@"):
        host_part, repo_part = value[4:].split(":", 1)
        host = host_part.lower()
        path = repo_part
        api_host = host
    elif "://" not in value and ":" in value:
        host_part, repo_part = value.split(":", 1)
        host = host_part.lower()
        path = repo_part
        ssh_info = ssh_host_info(host)
        api_host = (ssh_info.get("hostname") or host).lower()
        ssh_port = ssh_info.get("port", "")
    else:
        parsed = parse.urlparse(value)
        host = (parsed.hostname or "").lower()
        path = parsed.path.lstrip("/")
        api_host = host
    if path.endswith(".git"):
        path = path[:-4]
    parts = [item for item in path.split("/") if item]
    owner = parts[-2] if len(parts) >= 2 else ""
    repo = parts[-1] if parts else ""
    provider_source = f"{host} {api_host}"
    provider = "github" if "github" in provider_source else ("gitlab" if "gitlab" in provider_source else "unknown")
    gitlab_base_url = guess_gitlab_base_url(repo_path, "/".join(parts)) if provider == "gitlab" else ""
    return {
        "provider": provider,
        "host": host,
        "api_host": api_host,
        "ssh_port": ssh_port,
        "owner": owner,
        "repo": repo,
        "remote_url": remote_url,
        "project_path_with_namespace": "/".join(parts),
        "gitlab_base_url": gitlab_base_url,
    }

credential_cache = {}
commit_login_cache = {}
github_pull_cache = {}

def get_host_token(host):
    if host in credential_cache:
        return credential_cache[host]
    payload = f"protocol=https\nhost={host}\n"
    try:
        result = subprocess.run(
            ["git", "credential", "fill"],
            input=payload,
            text=True,
            capture_output=True,
            check=True,
            timeout=3,
            env={
                **os.environ,
                "GIT_TERMINAL_PROMPT": "0",
                "GCM_INTERACTIVE": "never",
            },
        )
    except Exception:
        credential_cache[host] = ""
        return ""
    token = ""
    for line in result.stdout.splitlines():
        if line.startswith("password="):
            token = line.split("=", 1)[1].strip()
            break
    credential_cache[host] = token
    return token

def http_get_json(url, token="", insecure=False):
    headers = {
        "User-Agent": "git-workload-report",
        "Accept": "application/json, application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = request.Request(url, headers=headers)
    context = ssl._create_unverified_context() if insecure else None
    with request.urlopen(req, timeout=6, context=context) as resp:
        return json.loads(resp.read().decode("utf-8"))

def github_commit_login(remote_info, sha):
    cache_key = (remote_info["host"], remote_info["owner"], remote_info["repo"], sha)
    if cache_key in commit_login_cache:
        return commit_login_cache[cache_key]
    token = get_host_token(remote_info["host"])
    if not token:
        commit_login_cache[cache_key] = ""
        return ""
    url = f'https://api.github.com/repos/{remote_info["owner"]}/{remote_info["repo"]}/commits/{sha}'
    try:
        data = http_get_json(url, token)
    except Exception:
        commit_login_cache[cache_key] = ""
        return ""
    login = ""
    if isinstance(data, dict):
        login = ((data.get("author") or {}).get("login") or (data.get("committer") or {}).get("login") or "").strip()
    commit_login_cache[cache_key] = login
    return login

def resolve_github_author_logins(remote_info, repo_commits):
    author_logins = {}
    commits_by_author = {}
    for commit in repo_commits:
        commits_by_author.setdefault(commit["author"], []).append(commit)
    for author, items in commits_by_author.items():
        logins = set()
        for commit in items:
            email = commit["email"]
            if email.endswith("@users.noreply.github.com"):
                prefix = email.split("@", 1)[0]
                if "+" in prefix:
                    logins.add(prefix.split("+", 1)[1])
                else:
                    logins.add(prefix)
        if not logins:
            email_prefix = items[0]["email"].split("@", 1)[0]
            if email_prefix and "." not in email_prefix:
                logins.add(email_prefix)
        for commit in items[:3]:
            login = github_commit_login(remote_info, commit["hash"])
            if login:
                logins.add(login)
                break
        author_logins[author] = sorted(logins)
    return author_logins

gitlab_project_id_cache = {}
gitlab_user_cache = {}
gitlab_pull_cache = {}
gitlab_api_base_cache = {}

def gitlab_api_base_url(remote_info):
    cache_key = (remote_info.get("host", ""), remote_info.get("project_path_with_namespace", ""))
    if cache_key in gitlab_api_base_cache:
        return gitlab_api_base_cache[cache_key]
    candidates = []
    configured_base_url = str(app_config.get("gitlab_api_base_url", "")).strip()
    if configured_base_url:
        candidates.append(configured_base_url.rstrip("/"))
    if remote_info.get("gitlab_base_url"):
        candidates.append(remote_info["gitlab_base_url"].rstrip("/"))
    api_host = remote_info.get("api_host") or remote_info.get("host") or ""
    if api_host:
        candidates.extend([
            f"http://{api_host}:8929/gitlab",
            f"http://{api_host}:8929",
            f"https://{api_host}/gitlab",
            f"https://{api_host}",
            f"http://{api_host}/gitlab",
            f"http://{api_host}",
        ])
    seen = set()
    for base_url in candidates:
        if not base_url or base_url in seen:
            continue
        seen.add(base_url)
        path = parse.quote(remote_info["project_path_with_namespace"], safe="")
        url = f"{base_url}/api/v4/projects/{path}"
        try:
            data = http_get_json(url, "", insecure=base_url.startswith("https://"))
        except Exception:
            continue
        if isinstance(data, dict) and data.get("path_with_namespace") == remote_info["project_path_with_namespace"]:
            gitlab_api_base_cache[cache_key] = base_url
            return base_url
    gitlab_api_base_cache[cache_key] = ""
    return ""

def gitlab_project_id(remote_info):
    cache_key = (remote_info["host"], remote_info["project_path_with_namespace"])
    if cache_key in gitlab_project_id_cache:
        return gitlab_project_id_cache[cache_key]
    base_url = gitlab_api_base_url(remote_info)
    if not base_url:
        gitlab_project_id_cache[cache_key] = ""
        return ""
    token = get_host_token(remote_info.get("api_host") or remote_info["host"])
    path = parse.quote(remote_info["project_path_with_namespace"], safe="")
    url = f'{base_url}/api/v4/projects/{path}'
    try:
        data = http_get_json(url, token, insecure=base_url.startswith("https://"))
    except Exception:
        gitlab_project_id_cache[cache_key] = ""
        return ""
    project_id = str(data.get("id", "")).strip() if isinstance(data, dict) else ""
    gitlab_project_id_cache[cache_key] = project_id
    return project_id

def gitlab_find_username(remote_info, author_name, author_email):
    cache_key = (remote_info["host"], author_name, author_email)
    if cache_key in gitlab_user_cache:
        return gitlab_user_cache[cache_key]
    base_url = gitlab_api_base_url(remote_info)
    token = get_host_token(remote_info.get("api_host") or remote_info["host"])
    if not base_url or not token:
        gitlab_user_cache[cache_key] = ""
        return ""
    candidates = []
    if author_email:
        candidates.append(author_email)
    if author_name:
        candidates.append(author_name)
    for candidate in candidates:
        query = parse.urlencode({"search": candidate, "active": "true"})
        url = f'{base_url}/api/v4/users?{query}'
        try:
            rows = http_get_json(url, token, insecure=base_url.startswith("https://"))
        except Exception:
            continue
        if not isinstance(rows, list):
            continue
        for row in rows:
            row_name = str(row.get("name", "")).strip().lower()
            row_username = str(row.get("username", "")).strip()
            row_email = str(row.get("public_email", "")).strip().lower()
            if author_email and row_email and row_email == author_email.lower():
                gitlab_user_cache[cache_key] = row_username
                return row_username
            if author_name and row_name == author_name.lower():
                gitlab_user_cache[cache_key] = row_username
                return row_username
        if rows:
            username = str(rows[0].get("username", "")).strip()
            if username:
                gitlab_user_cache[cache_key] = username
                return username
    gitlab_user_cache[cache_key] = ""
    return ""

def resolve_gitlab_author_logins(remote_info, repo_commits):
    author_logins = {}
    commits_by_author = {}
    for commit in repo_commits:
        commits_by_author.setdefault(commit["author"], []).append(commit)
    for author, items in commits_by_author.items():
        logins = set()
        emails = [commit["email"] for commit in items if commit["email"]]
        if author:
            compact_author = re.sub(r"[^0-9a-zA-Z._-]+", "", author.strip().lower())
            if compact_author:
                logins.add(compact_author)
        if emails:
            email_prefix = emails[0].split("@", 1)[0].strip().lower()
            if email_prefix:
                logins.add(email_prefix)
        username = gitlab_find_username(remote_info, author, emails[0] if emails else "")
        if username:
            logins.add(username)
        author_logins[author] = sorted(logins)
    return author_logins

def fetch_gitlab_merge_requests(remote_info, start_date, author_logins):
    project_id = gitlab_project_id(remote_info)
    base_url = gitlab_api_base_url(remote_info)
    token = get_host_token(remote_info.get("api_host") or remote_info["host"])
    if not project_id or not base_url:
        return []
    cache_key = (remote_info["host"], project_id, start_date)
    if cache_key in gitlab_pull_cache:
        return gitlab_pull_cache[cache_key]
    page = 1
    results = []
    while True:
        query = parse.urlencode({
            "state": "all",
            "scope": "all",
            "created_after": f"{start_date}T00:00:00Z",
            "order_by": "created_at",
            "sort": "desc",
            "per_page": 100,
            "page": page,
        })
        url = f'{base_url}/api/v4/projects/{project_id}/merge_requests?{query}'
        try:
            rows = http_get_json(url, token, insecure=base_url.startswith("https://"))
        except Exception:
            break
        if not rows:
            break
        for row in rows:
            results.append({
                "number": row.get("iid"),
                "title": row.get("title", ""),
                "login": (((row.get("author") or {}).get("username")) or "").strip(),
                "created_at": row.get("created_at"),
                "merged_at": row.get("merged_at"),
                "state": row.get("state", ""),
            })
        page += 1
    gitlab_pull_cache[cache_key] = results
    return results

def fetch_github_pull_requests(remote_info, start_date):
    cache_key = (remote_info["host"], remote_info["owner"], remote_info["repo"], start_date)
    if cache_key in github_pull_cache:
        return github_pull_cache[cache_key]
    token = get_host_token(remote_info["host"])
    if not token:
        github_pull_cache[cache_key] = []
        return []
    start_dt = datetime.fromisoformat(f"{start_date}T00:00:00")
    pulls = []
    page = 1
    while True:
        query = parse.urlencode({
            "state": "all",
            "sort": "created",
            "direction": "desc",
            "per_page": 100,
            "page": page,
        })
        url = f'https://api.github.com/repos/{remote_info["owner"]}/{remote_info["repo"]}/pulls?{query}'
        try:
            rows = http_get_json(url, token)
        except Exception:
            break
        if not rows:
            break
        stop = False
        for row in rows:
            created_at = row.get("created_at", "")
            if not created_at:
                continue
            created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00")).replace(tzinfo=None)
            if created_dt < start_dt:
                stop = True
                continue
            pulls.append({
                "number": row.get("number"),
                "title": row.get("title", ""),
                "login": ((row.get("user") or {}).get("login") or "").strip(),
                "created_at": created_at,
                "merged_at": row.get("merged_at"),
                "state": row.get("state", ""),
            })
        if stop:
            break
        page += 1
    github_pull_cache[cache_key] = pulls
    return pulls

def build_pull_requests(repo_infos, commits, start_date):
    """按仓库读取 PR / MR 明细，并把平台账号映射回本地提交作者。

    进度文案统一写「读取 Git PR」，不写死平台名：远端可能是 GitHub、GitLab，也可能是
    Gitee 或公司自建服务，脚本没有资格在这里替用户断言是哪一家。
    GitHub 和 GitLab 的接口形态本来就不一样，各自保留各自的读取实现，不强行抽出中间层；
    这里只统一三步顺序：先判平台，再取账号映射，最后取 PR 列表。
    平台不认识时不静默跳过，打一条明确的跳过原因，避免用户看到 PR 数为 0 却不知道为什么。"""
    pull_requests = []
    for repo_info in repo_infos:
        remote_info = repo_info["remote"]
        repo_commits = [commit for commit in commits if commit["project_path"] == repo_info["path"]]
        if not repo_commits:
            continue

        provider = remote_info["provider"]
        if provider not in ("github", "gitlab"):
            print_progress(f'跳过 Git PR：{repo_info["name"]}，远端不是 GitHub / GitLab')
            continue

        # 账号映射本身就要走网络，进度先打印，避免用户以为卡住了
        print_progress(f'读取 Git PR：{repo_info["name"]}')
        if provider == "gitlab":
            author_logins = resolve_gitlab_author_logins(remote_info, repo_commits)
        else:
            author_logins = resolve_github_author_logins(remote_info, repo_commits)

        login_to_authors = {}
        for author, logins in author_logins.items():
            for login in logins:
                login_to_authors.setdefault(login, set()).add(author)
        if not login_to_authors:
            continue

        if provider == "gitlab":
            pulls = fetch_gitlab_merge_requests(remote_info, start_date, login_to_authors.keys())
        else:
            pulls = fetch_github_pull_requests(remote_info, start_date)

        for pr in pulls:
            login = pr["login"]
            if not login or login not in login_to_authors:
                continue
            for author in sorted(login_to_authors[login]):
                pull_requests.append({
                    "project": repo_info["name"],
                    "project_path": repo_info["path"],
                    "author": author,
                    "login": login,
                    "number": pr["number"],
                    "title": pr["title"],
                    "created_at": pr["created_at"],
                    "merged_at": pr["merged_at"],
                    "state": pr["state"],
                })
    return pull_requests

def read_directory_config():
    if not directory_config_path:
        return []
    print_progress(f"读取仓库清单：{directory_config_path}")
    paths = []
    with open(directory_config_path, "r", encoding="utf-8") as file:
        for line in file:
            value = line.strip()
            if value and not value.startswith("#"):
                paths.append(value)
    print_progress(f"仓库清单读取完成，共 {len(paths)} 个路径")
    return paths

def discover_repos():
    print_progress("开始识别 Git 仓库")
    configured_paths = read_directory_config()
    if directory_config_path:
        candidates = [*configured_paths, *input_paths]
    else:
        candidates = input_paths or [default_dir]
    roots = []
    print_progress(f"待检查路径数量：{len(candidates)}")
    for index, candidate in enumerate(candidates, start=1):
        path = os.path.realpath(candidate)
        print_progress(f"检查路径 {index}/{len(candidates)}：{path}")
        if is_git_repo(path):
            root = git_root(path)
            print_progress(f"识别到仓库：{root}")
            roots.append(root)
            continue
        if not input_paths and os.path.isdir(path):
            for name in sorted(os.listdir(path)):
                child = os.path.join(path, name)
                if os.path.isdir(child) and is_git_repo(child):
                    root = git_root(child)
                    print_progress(f"识别到子仓库：{root}")
                    roots.append(root)
    repos = sorted(set(roots))
    print_progress(f"Git 仓库识别完成，共 {len(repos)} 个仓库")
    return repos

def parse_numstat_line(line):
    parts = line.split("\t")
    if len(parts) < 3:
        return None
    if not parts[0].isdigit() or not parts[1].isdigit():
        return None
    return {
        "file": parts[2],
        "added": int(parts[0]),
        "deleted": int(parts[1]),
    }

def parse_commits(repo_path):
    project_name = os.path.basename(repo_path)
    print_progress(f"开始读取仓库提交：{project_name}（{repo_path}）")
    args = [
        "log",
        f"--after={collect_time_start}",
        f"--before={collect_time_end}",
        "--date=iso-strict",
        "--pretty=format:--GIT-WORKLOAD-COMMIT--%n%H%n%an%n%ae%n%ad%n%P%n%s",
        "--numstat",
    ]
    if author_filter:
        args.insert(1, f"--author={author_filter}")
    raw = run_git(repo_path, args)
    print_progress(f"Git 日志读取完成：{project_name}，开始解析提交记录")
    commits = []
    current = None
    header = []

    for line in raw.splitlines():
        if line.startswith("--GIT-WORKLOAD-COMMIT--"):
            if current:
                commits.append(current)
            current = None
            header = []
            continue
        if current is None and len(header) < 6:
            header.append(line)
            if len(header) == 6:
                commit_time = datetime.fromisoformat(header[3])
                parents = [item for item in header[4].split() if item]
                current = {
                    "project": project_name,
                    "project_path": repo_path,
                    "hash": header[0],
                    "short_hash": header[0][:8],
                    "author": header[1],
                    "email": header[2],
                    "time": header[3],
                    "parents": parents,
                    "is_merge": len(parents) > 1,
                    "date": commit_time.date().isoformat(),
                    "hour": commit_time.strftime("%H"),
                    "week_day": str(commit_time.isoweekday()),
                    "subject": header[5],
                    "added": 0,
                    "deleted": 0,
                    "files": [],
                }
            continue
        if current is None:
            continue
        stat = parse_numstat_line(line)
        if stat:
            current["files"].append(stat)
            current["added"] += stat["added"]
            current["deleted"] += stat["deleted"]

    if current:
        commits.append(current)
    print_progress(f"仓库解析完成：{project_name}，提交 {len(commits)} 次")
    return commits

def collect_conflict_merges(repo_path):
    """识别真正动过手的合并：combined diff（--cc）里出现的文件 = 与所有父提交都不同 = 冲突解决/手工调整。返回 {hash: [文件...]}"""
    try:
        raw = run_git(repo_path, [
            "log",
            "--merges",
            f"--after={collect_time_start}",
            f"--before={collect_time_end}",
            "--diff-merges=cc",
            "--name-only",
            "--pretty=format:--GW-MERGE--%n%H",
        ])
    except Exception:
        return {}
    result = {}
    current_hash = None
    expect_hash = False
    for line in raw.splitlines():
        if line.startswith("--GW-MERGE--"):
            expect_hash = True
            current_hash = None
            continue
        if expect_hash:
            current_hash = line.strip()
            result[current_hash] = []
            expect_hash = False
            continue
        if current_hash and line.strip():
            result[current_hash].append(line.strip())
    return {h: files for h, files in result.items() if files}

def collect_branches(repo_path):
    """采集分支概览：本地 + 远端分支的最后提交时间、最后提交人、是否已并入 HEAD、是否僵尸（>90 天未动）。"""
    project_name = os.path.basename(repo_path)
    info = {
        "project": project_name,
        "total": 0,
        "local": 0,
        "remote": 0,
        "merged": 0,
        "unmerged": 0,
        "stale": 0,
        "by_author": {},
        "categories": {},
        "branches": [],
    }
    try:
        raw = run_git(repo_path, [
            "for-each-ref", "refs/heads", "refs/remotes",
            "--format=%(refname:short)|%(committerdate:short)|%(authorname)",
        ])
    except Exception:
        return info
    merged_set = set()
    try:
        merged_raw = run_git(repo_path, ["branch", "-a", "--merged", "HEAD", "--format=%(refname:short)"])
        merged_set = {line.strip() for line in merged_raw.splitlines() if line.strip()}
    except Exception:
        pass
    today = datetime.now().date()
    seen_names = set()
    for line in raw.splitlines():
        parts = line.split("|")
        if len(parts) < 3:
            continue
        name, last_date, last_author = parts[0], parts[1], parts[2]
        if name.endswith("/HEAD") or name == "HEAD":
            continue
        is_remote = "/" in name and name.split("/", 1)[0] in ("origin", "upstream")
        short_name = name.split("/", 1)[1] if is_remote else name
        # 本地与远端同名分支只记一次，优先保留本地
        if short_name in seen_names and is_remote:
            continue
        seen_names.add(short_name)
        try:
            days_idle = (today - datetime.fromisoformat(last_date).date()).days
        except (TypeError, ValueError):
            days_idle = 0
        stale = days_idle > 90
        merged = name in merged_set
        prefix = short_name.split("/", 1)[0].lower() if "/" in short_name else "其他"
        if prefix not in ("feature", "feat", "fix", "bugfix", "hotfix", "release", "dev", "develop", "test", "chore"):
            prefix = "其他"
        info["total"] += 1
        info["remote" if is_remote else "local"] += 1
        info["merged" if merged else "unmerged"] += 1
        if stale:
            info["stale"] += 1
        info["by_author"][last_author] = info["by_author"].get(last_author, 0) + 1
        info["categories"][prefix] = info["categories"].get(prefix, 0) + 1
        info["branches"].append({
            "name": short_name,
            "is_remote": is_remote,
            "last_date": last_date,
            "last_author": last_author,
            "merged": merged,
            "stale": stale,
            "days_idle": days_idle,
        })
    info["branches"].sort(key=lambda b: b["last_date"], reverse=True)
    info["branches"] = info["branches"][:50]
    return info

def format_number(value):
    return f"{value:,}"

def date_diff_days(start_date, end_date):
    try:
        start = datetime.fromisoformat(start_date)
        end = datetime.fromisoformat(end_date)
    except (TypeError, ValueError):
        return 1
    return max((end - start).days + 1, 1)

def estimate_hours(commits):
    by_date = {}
    for commit in commits:
        by_date.setdefault(commit["date"], []).append(int(commit["hour"]))
    total_hours = 0
    for hours in by_date.values():
        total_hours += max(hours) - min(hours) + 1
    return len(by_date), total_hours

def group_count(commits, key, seed=None):
    result = {item: 0 for item in (seed or [])}
    for commit in commits:
        value = commit[key]
        result[value] = result.get(value, 0) + 1
    return result

def print_rows(headers, rows):
    if not rows:
        print("  当前筛选条件下没有数据")
        return
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(str(value)))
    header_line = "  " + "  ".join(str(value).ljust(widths[index]) for index, value in enumerate(headers))
    separator = "  " + "  ".join("-" * width for width in widths)
    print(header_line)
    print(separator)
    for row in rows:
        print("  " + "  ".join(str(value).ljust(widths[index]) for index, value in enumerate(row)))

# ===== 增量展示：综合指标计算（应给尽给，全量指标） =====
weekday_labels = {"1": "周一", "2": "周二", "3": "周三", "4": "周四", "5": "周五", "6": "周六", "7": "周日"}
night_hours = {"22", "23", "00", "01", "02", "03", "04"}
worktime_hours = {"09", "10", "11", "12", "13", "14", "15", "16", "17", "18"}
bug_keywords = ("fix", "bug", "patch", "hotfix", "resolve", "修复", "解决")
refactor_keywords = ("refactor", "cleanup", "clean", "optimize", "optimise", "restructure", "perf", "重构", "优化", "整理")
bot_keywords = ("bot", "[bot]", "ci", "jenkins", "github-actions", "automation", "runner")


def commit_datetime(commit):
    """把 date + hour 組合成 naive datetime，避免 iso 偏移解析差异。"""
    date = commit["date"]
    hour = int(commit["hour"])
    return datetime(int(date[:4]), int(date[5:7]), int(date[8:10]), hour)


def compute_streaks(dates):
    """返回 (最长连续天数, 当前连续天数)。连续按自然日相邻判断。"""
    if not dates:
        return 0, 0
    sorted_dates = sorted({datetime.fromisoformat(d) for d in dates})
    longest = 1
    current = 1
    for prev, cur in zip(sorted_dates, sorted_dates[1:]):
        if (cur - prev).days == 1:
            current += 1
            longest = max(longest, current)
        else:
            current = 1
    cur_streak = 1
    for idx in range(len(sorted_dates) - 1, 0, -1):
        if (sorted_dates[idx] - sorted_dates[idx - 1]).days == 1:
            cur_streak += 1
        else:
            break
    return longest, cur_streak


def gini(values):
    vals = sorted(values)
    n = len(vals)
    if n == 0 or sum(vals) == 0:
        return 0.0
    cum = sum(i * v for i, v in enumerate(vals, start=1))
    total = sum(vals)
    return (2 * cum) / (n * total) - (n + 1) / n


def classify_subject(subject):
    text = (subject or "").lower()
    if any(k in text for k in bug_keywords):
        return "bug"
    if any(k in text for k in refactor_keywords):
        return "refactor"
    return "other"

conventional_types = ("feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert")
merge_branch_pattern = re.compile(r"Merge branch '([^']+)'(?:\s+into\s+(\S+))?")
merge_pr_pattern = re.compile(r"Merge (?:pull request|PR) #?(\d+)(?:\s+from\s+(\S+))?", re.IGNORECASE)
revert_pattern = re.compile(r'^Revert\s+"(.*)"')

def classify_commit_type(commit):
    """按 Conventional Commits 规范细分提交类型，非规范提交用关键词兜底。"""
    subject = (commit.get("subject") or "").strip()
    lower = subject.lower()
    if commit.get("is_merge") or lower.startswith("merge "):
        return "merge"
    if lower.startswith("revert"):
        return "revert"
    matched = re.match(r"^([a-z]+)(\([^)]*\))?!?:", lower)
    if matched and matched.group(1) in conventional_types:
        return matched.group(1)
    if any(k in lower for k in bug_keywords):
        return "fix"
    if any(k in lower for k in refactor_keywords):
        return "refactor"
    if any(k in lower for k in ("doc", "readme", "文档")):
        return "docs"
    if any(k in lower for k in ("test", "测试")):
        return "test"
    return "other"

def sorted_count_list(counter, key_name, limit):
    """{名称: 次数} → 按次数降序、名称升序取前 N，输出 [{key_name, count}]。Python/JS 需保持同一排序规则。"""
    items = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))
    return [{key_name: k, "count": v} for k, v in items[:limit]]


def build_metrics(commits):
    """全量计算工作量指标，返回结构化 dict。无提交时返回空骨架。"""
    empty = {
        "time_span": {},
        "cadence": {},
        "monthly_trend": [],
        "code_changes": {"top_files": []},
        "concentration": {},
        "time_health": {},
        "work_categories": {},
        "commit_quality": {},
        "merge_analysis": {},
        "revert_analysis": {},
        "commit_types": {},
        "ownership": {},
        "authors": [],
        "projects": [],
    }
    if not commits:
        return empty

    dates = [c["date"] for c in commits]
    first_date = min(dates)
    last_date = max(dates)
    span_days = date_diff_days(first_date, last_date)
    active_day_set = set(dates)
    active_days = len(active_day_set)
    active_day_ratio = active_days / span_days * 100 if span_days else 0

    by_day = {}
    for c in commits:
        by_day.setdefault(c["date"], 0)
        by_day[c["date"]] += 1
    max_day_count = max(by_day.values())
    peak_day_date = [d for d, n in by_day.items() if n == max_day_count][0]
    avg_per_active_day = len(commits) / active_days if active_days else 0
    commit_spike = (max_day_count / avg_per_active_day - 1) if avg_per_active_day else 0
    longest_streak, current_streak = compute_streaks(dates)

    sorted_by_time = sorted(commits, key=lambda c: c["time"])
    intervals = []
    for a, b in zip(sorted_by_time, sorted_by_time[1:]):
        delta = (commit_datetime(b) - commit_datetime(a)).total_seconds() / 60.0
        if delta >= 0:
            intervals.append(delta)
    avg_interval = sum(intervals) / len(intervals) if intervals else 0

    week_counts = group_count(commits, "week_day", list(weekday_labels.keys()))
    peak_weekday = max(week_counts.items(), key=lambda kv: kv[1])[0]
    hour_counts = group_count(commits, "hour", [str(i).zfill(2) for i in range(24)])
    peak_hour = max(hour_counts.items(), key=lambda kv: kv[1])[0]

    monthly = {}
    for c in commits:
        month = c["date"][:7]
        entry = monthly.setdefault(month, {"month": month, "commits": 0, "added": 0, "deleted": 0, "authors": set(), "active_days": set()})
        entry["commits"] += 1
        entry["added"] += c["added"]
        entry["deleted"] += c["deleted"]
        entry["authors"].add(c["author"])
        entry["active_days"].add(c["date"])
    monthly_trend = []
    for m in sorted(monthly.keys()):
        e = monthly[m]
        monthly_trend.append({
            "month": m,
            "commits": e["commits"],
            "added": e["added"],
            "deleted": e["deleted"],
            "authors": len(e["authors"]),
            "active_days": len(e["active_days"]),
        })

    total_added = sum(c["added"] for c in commits)
    total_deleted = sum(c["deleted"] for c in commits)
    total_changed = total_added + total_deleted
    avg_lines = total_changed / len(commits) if commits else 0
    max_commit = max(commits, key=lambda c: c["added"] + c["deleted"])
    max_total = max_commit["added"] + max_commit["deleted"]
    total_files_changed = sum(len(c["files"]) for c in commits)
    file_map = {}
    for c in commits:
        for f in c["files"]:
            fe = file_map.setdefault(f["file"], {"file": f["file"], "changes": 0, "added": 0, "deleted": 0})
            fe["changes"] += 1
            fe["added"] += f["added"]
            fe["deleted"] += f["deleted"]
    unique_files = len(file_map)
    top_files = sorted(file_map.values(), key=lambda x: x["changes"], reverse=True)[:10]
    empty_commits = sum(1 for c in commits if c["added"] == 0 and c["deleted"] == 0 and not c["files"])
    large_commits = sum(1 for c in commits if (c["added"] + c["deleted"]) > 500)
    churn_ratio = total_deleted / total_changed * 100 if total_changed else 0

    author_counts = group_count(commits, "author")
    counts_sorted = sorted(author_counts.items(), key=lambda kv: kv[1], reverse=True)
    total_commits_n = len(commits)
    top1_ratio = (counts_sorted[0][1] / total_commits_n * 100) if counts_sorted else 0
    top2_ratio = (sum(n for _, n in counts_sorted[:2]) / total_commits_n * 100) if counts_sorted else 0
    gini_val = gini([n for _, n in counts_sorted])
    bus_factor = 0
    cum = 0
    for _, n in counts_sorted:
        cum += n
        bus_factor += 1
        if cum >= total_commits_n * 0.5:
            break
    bus_factor = bus_factor or len(counts_sorted)
    pareto_80 = 0
    cum = 0
    for _, n in counts_sorted:
        cum += n
        pareto_80 += 1
        if cum >= total_commits_n * 0.8:
            break
    pareto_80 = pareto_80 or len(counts_sorted)

    night_commits = sum(1 for c in commits if c["hour"] in night_hours)
    weekend_commits = sum(1 for c in commits if c["week_day"] in ("6", "7"))
    worktime_commits = sum(1 for c in commits if c["hour"] in worktime_hours)
    offhours_commits = len(commits) - worktime_commits

    cat = {"bug": 0, "refactor": 0, "other": 0}
    for c in commits:
        cat[classify_subject(c["subject"])] += 1
    bug_ratio = cat["bug"] / total_commits_n if total_commits_n else 0
    refactor_ratio = cat["refactor"] / total_commits_n if total_commits_n else 0
    other_ratio = cat["other"] / total_commits_n if total_commits_n else 0

    merge_commits = sum(1 for c in commits if c.get("is_merge") or str(c.get("subject", "")).lower().startswith("merge"))
    bot_commits = sum(1 for c in commits if any(k in (c["author"] + c["email"]).lower() for k in bot_keywords))
    avg_subject_len = sum(len(c["subject"] or "") for c in commits) / total_commits_n if total_commits_n else 0
    avg_subject_words = sum(len((c["subject"] or "").split()) for c in commits) / total_commits_n if total_commits_n else 0

    author_metrics = []
    for author, n in counts_sorted:
        ac = [c for c in commits if c["author"] == author]
        adates = [c["date"] for c in ac]
        a_added = sum(c["added"] for c in ac)
        a_deleted = sum(c["deleted"] for c in ac)
        a_active = len(set(adates))
        a_first = min(adates)
        a_last = max(adates)
        a_longest, a_current = compute_streaks(adates)
        a_peak_hour_raw = max(group_count(ac, "hour", [str(i).zfill(2) for i in range(24)]).items(), key=lambda kv: kv[1])[0]
        a_peak_hour = f"{a_peak_hour_raw}:00"
        a_peak_wd = max(group_count(ac, "week_day", list(weekday_labels.keys())).items(), key=lambda kv: kv[1])[0]
        a_files = len({f["file"] for c in ac for f in c["files"]})
        author_metrics.append({
            "author": author,
            "commits": n,
            "commit_ratio": n / total_commits_n * 100 if total_commits_n else 0,
            "added": a_added,
            "deleted": a_deleted,
            "active_days": a_active,
            "first_commit": a_first,
            "last_commit": a_last,
            "longest_streak": a_longest,
            "current_streak": a_current,
            "peak_hour": a_peak_hour,
            "peak_weekday": weekday_labels.get(a_peak_wd, a_peak_wd),
            "avg_per_active_day": n / a_active if a_active else 0,
            "unique_files": a_files,
        })

    project_metrics = []
    for project in sorted({c["project"] for c in commits}):
        pc = [c for c in commits if c["project"] == project]
        project_metrics.append({
            "project": project,
            "commits": len(pc),
            "added": sum(c["added"] for c in pc),
            "deleted": sum(c["deleted"] for c in pc),
            "authors": len({c["author"] for c in pc}),
            "active_days": len({c["date"] for c in pc}),
        })

    # ===== 合并分析：谁做的合并、来源分支、谁解决的冲突、冲突热点文件 =====
    merges = [c for c in commits if c.get("is_merge")]
    merge_author_counts = {}
    merge_source_counts = {}
    pr_merge_count = 0
    for c in merges:
        merge_author_counts[c["author"]] = merge_author_counts.get(c["author"], 0) + 1
        subject = c.get("subject") or ""
        pr_match = merge_pr_pattern.search(subject)
        if pr_match:
            pr_merge_count += 1
            if pr_match.group(2):
                merge_source_counts[pr_match.group(2)] = merge_source_counts.get(pr_match.group(2), 0) + 1
            continue
        br_match = merge_branch_pattern.search(subject)
        if br_match:
            merge_source_counts[br_match.group(1)] = merge_source_counts.get(br_match.group(1), 0) + 1
    conflict_merges = [c for c in merges if c.get("conflict_files")]
    conflict_resolver_counts = {}
    conflict_file_counts = {}
    for c in conflict_merges:
        conflict_resolver_counts[c["author"]] = conflict_resolver_counts.get(c["author"], 0) + 1
        for name in c.get("conflict_files") or []:
            conflict_file_counts[name] = conflict_file_counts.get(name, 0) + 1
    merge_analysis = {
        "total_merges": len(merges),
        "merge_ratio": len(merges) / total_commits_n * 100 if total_commits_n else 0,
        "pr_merges": pr_merge_count,
        "branch_merges": len(merges) - pr_merge_count,
        "merge_by_author": sorted_count_list(merge_author_counts, "author", 10),
        "merge_sources": sorted_count_list(merge_source_counts, "branch", 10),
        "conflict_merges": len(conflict_merges),
        "conflict_ratio": len(conflict_merges) / len(merges) * 100 if merges else 0,
        "conflict_resolvers": sorted_count_list(conflict_resolver_counts, "author", 10),
        "conflict_files": sorted_count_list(conflict_file_counts, "file", 10),
    }

    # ===== 问题溯源：谁在回滚救火、谁的提交被回滚、Bug 高发文件 =====
    reverts = []
    revert_author_counts = {}
    subject_author_index = {}
    for c in commits:
        subj = (c.get("subject") or "").strip()
        if not revert_pattern.match(subj) and subj not in subject_author_index:
            subject_author_index[subj] = c["author"]
    for c in commits:
        matched = revert_pattern.match((c.get("subject") or "").strip())
        if matched:
            reverts.append((c, matched.group(1)))
            revert_author_counts[c["author"]] = revert_author_counts.get(c["author"], 0) + 1
    reverted_author_counts = {}
    for _, orig_subject in reverts:
        orig_author = subject_author_index.get(orig_subject.strip())
        if orig_author:
            reverted_author_counts[orig_author] = reverted_author_counts.get(orig_author, 0) + 1
    bug_prone_counts = {}
    for c in commits:
        if classify_subject(c.get("subject")) == "bug":
            for f in c["files"]:
                bug_prone_counts[f["file"]] = bug_prone_counts.get(f["file"], 0) + 1
    revert_analysis = {
        "revert_commits": len(reverts),
        "revert_ratio": len(reverts) / total_commits_n * 100 if total_commits_n else 0,
        "revert_by_author": sorted_count_list(revert_author_counts, "author", 10),
        "reverted_authors": sorted_count_list(reverted_author_counts, "author", 10),
        "bug_prone_files": sorted_count_list(bug_prone_counts, "file", 10),
    }

    # ===== 提交类型细分（Conventional Commits）=====
    type_order = ["feat", "fix", "refactor", "docs", "test", "style", "perf", "build", "ci", "chore", "revert", "merge", "other"]
    type_counts = {}
    author_type_counts = {}
    for c in commits:
        c_type = classify_commit_type(c)
        type_counts[c_type] = type_counts.get(c_type, 0) + 1
        author_type_counts.setdefault(c["author"], {})
        author_type_counts[c["author"]][c_type] = author_type_counts[c["author"]].get(c_type, 0) + 1
    type_distribution = [
        {"type": t, "count": type_counts[t], "ratio": type_counts[t] / total_commits_n * 100 if total_commits_n else 0}
        for t in type_order if type_counts.get(t)
    ]
    types_by_author = []
    for author, _n in counts_sorted:
        row = {"author": author}
        for t in type_order:
            row[t] = author_type_counts.get(author, {}).get(t, 0)
        types_by_author.append(row)
    commit_types = {
        "distribution": type_distribution,
        "by_author": types_by_author,
    }

    # ===== 文件所有权与协作：主要负责人、知识孤岛、协作对 =====
    file_author_commits = {}
    for c in commits:
        for f in c["files"]:
            file_author_commits.setdefault(f["file"], {})
            file_author_commits[f["file"]][c["author"]] = file_author_commits[f["file"]].get(c["author"], 0) + 1
    total_tracked_files = len(file_author_commits)
    single_owner_files = sum(1 for amap in file_author_commits.values() if len(amap) == 1)
    shared_files = total_tracked_files - single_owner_files
    file_owners = []
    for entry in top_files:
        amap = file_author_commits.get(entry["file"], {})
        if not amap:
            continue
        owner, owner_n = sorted(amap.items(), key=lambda kv: (-kv[1], kv[0]))[0]
        file_total = sum(amap.values())
        file_owners.append({
            "file": entry["file"],
            "owner": owner,
            "owner_commits": owner_n,
            "total_commits": file_total,
            "owner_ratio": owner_n / file_total * 100 if file_total else 0,
            "author_count": len(amap),
        })
    pair_counts = {}
    for amap in file_author_commits.values():
        authors_sorted = sorted(amap.keys())
        if len(authors_sorted) < 2:
            continue
        for i in range(len(authors_sorted)):
            for j in range(i + 1, len(authors_sorted)):
                key = f"{authors_sorted[i]} ↔ {authors_sorted[j]}"
                pair_counts[key] = pair_counts.get(key, 0) + 1
    ownership = {
        "total_files": total_tracked_files,
        "single_owner_files": single_owner_files,
        "single_owner_ratio": single_owner_files / total_tracked_files * 100 if total_tracked_files else 0,
        "shared_files": shared_files,
        "file_owners": file_owners,
        "collaboration_pairs": sorted_count_list(pair_counts, "pair", 5),
    }

    return {
        "time_span": {
            "first_commit_date": first_date,
            "last_commit_date": last_date,
            "span_days": span_days,
            "active_days": active_days,
            "active_day_ratio": active_day_ratio,
        },
        "cadence": {
            "avg_commits_per_active_day": avg_per_active_day,
            "max_commits_in_one_day": max_day_count,
            "peak_day_date": peak_day_date,
            "commit_spike": commit_spike,
            "longest_streak": longest_streak,
            "current_streak": current_streak,
            "avg_interval_minutes": avg_interval,
            "peak_weekday": weekday_labels.get(peak_weekday, peak_weekday),
            "peak_hour": f"{peak_hour}:00",
        },
        "monthly_trend": monthly_trend,
        "code_changes": {
            "avg_lines_per_commit": avg_lines,
            "max_commit_added": max_commit["added"],
            "max_commit_deleted": max_commit["deleted"],
            "max_commit_total": max_total,
            "max_commit_author": max_commit["author"],
            "max_commit_date": max_commit["date"],
            "max_commit_subject": max_commit["subject"],
            "total_files_changed": total_files_changed,
            "unique_files": unique_files,
            "empty_commits": empty_commits,
            "large_commits": large_commits,
            "churn_ratio": churn_ratio,
            "top_files": top_files,
        },
        "concentration": {
            "top1_ratio": top1_ratio,
            "top2_ratio": top2_ratio,
            "gini": gini_val,
            "bus_factor": bus_factor,
            "pareto_80": pareto_80,
        },
        "time_health": {
            "night_commits": night_commits,
            "night_ratio": night_commits / total_commits_n * 100 if total_commits_n else 0,
            "weekend_commits": weekend_commits,
            "weekend_ratio": weekend_commits / total_commits_n * 100 if total_commits_n else 0,
            "worktime_commits": worktime_commits,
            "worktime_ratio": worktime_commits / total_commits_n * 100 if total_commits_n else 0,
            "offhours_commits": offhours_commits,
            "offhours_ratio": offhours_commits / total_commits_n * 100 if total_commits_n else 0,
        },
        "work_categories": {
            "bug_fix_commits": cat["bug"],
            "bug_fix_ratio": bug_ratio * 100,
            "refactor_commits": cat["refactor"],
            "refactor_ratio": refactor_ratio * 100,
            "other_commits": cat["other"],
            "other_ratio": other_ratio * 100,
        },
        "commit_quality": {
            "merge_commits": merge_commits,
            "merge_ratio": merge_commits / total_commits_n * 100 if total_commits_n else 0,
            "bot_commits": bot_commits,
            "avg_subject_length": avg_subject_len,
            "avg_subject_words": avg_subject_words,
        },
        "merge_analysis": merge_analysis,
        "revert_analysis": revert_analysis,
        "commit_types": commit_types,
        "ownership": ownership,
        "authors": author_metrics,
        "projects": project_metrics,
    }


def print_branch_overview(branch_infos):
    """打印仓库级分支概览（数据来自采集阶段，不受提交过滤影响）。"""
    infos = [b for b in branch_infos if b.get("total")]
    if not infos:
        return
    print("分支概览")
    for info in infos:
        print(f"  {info['project']}：共 {info['total']} 条（本地 {info['local']} / 远端 {info['remote']}）")
        print(f"    已并入 HEAD：{info['merged']} 条 / 未并入：{info['unmerged']} 条 / 僵尸分支（>90 天未动）：{info['stale']} 条")
        if info.get("categories"):
            cat_parts = [f"{k} {v}" for k, v in sorted(info["categories"].items(), key=lambda kv: (-kv[1], kv[0]))]
            print(f"    命名类别：{'，'.join(cat_parts)}")
        if info.get("by_author"):
            author_parts = [f"{k} {v}" for k, v in sorted(info["by_author"].items(), key=lambda kv: (-kv[1], kv[0]))[:8]]
            print(f"    最后提交人分布：{'，'.join(author_parts)}")
        stale_list = [b for b in info.get("branches", []) if b.get("stale")][:5]
        if stale_list:
            print("    最久未动分支：")
            for b in sorted(stale_list, key=lambda x: -x["days_idle"]):
                print(f"      {b['name']}（{b['last_author']}，{b['last_date']}，闲置 {b['days_idle']} 天）")
    print()

def print_metrics_terminal(metrics):
    """增量打印全量指标章节（保留原有章节，仅追加新内容）。"""
    ts = metrics.get("time_span", {})
    cd = metrics.get("cadence", {})
    cc = metrics.get("code_changes", {})
    cn = metrics.get("concentration", {})
    th = metrics.get("time_health", {})
    wc = metrics.get("work_categories", {})
    cq = metrics.get("commit_quality", {})

    if ts:
        print("时间跨度与活跃度")
        print(f"  首次提交：{ts.get('first_commit_date', '-')}")
        print(f"  最近提交：{ts.get('last_commit_date', '-')}")
        print(f"  时间跨度：{ts.get('span_days', 0)} 天")
        print(f"  活跃天数：{ts.get('active_days', 0)} 天")
        print(f"  活跃密度：{ts.get('active_day_ratio', 0):.1f}%（活跃天数 / 时间跨度）")
        print()

    if cd:
        print("提交节奏")
        print(f"  最忙一天：{cd.get('peak_day_date', '-')}（{cd.get('max_commits_in_one_day', 0)} 次）")
        print(f"  提交尖峰：{cd.get('commit_spike', 0):.1f}x（最忙日 vs 日均活跃日）")
        print(f"  最长连续提交：{cd.get('longest_streak', 0)} 天")
        print(f"  当前连续提交：{cd.get('current_streak', 0)} 天")
        print(f"  平均提交间隔：{cd.get('avg_interval_minutes', 0):.0f} 分钟")
        print(f"  最活跃星期：{cd.get('peak_weekday', '-')}")
        print(f"  最活跃时段：{cd.get('peak_hour', '-')}")
        print()

    if metrics.get("monthly_trend"):
        print("月度提交趋势")
        trend_rows = [[m["month"], format_number(m["commits"]), format_number(m["added"]), format_number(m["deleted"]), m["authors"], m["active_days"]] for m in metrics["monthly_trend"]]
        print_rows(["月份", "提交", "新增", "删除", "开发者", "活跃天"], trend_rows)
        print()

    if cc:
        print("代码改动概览")
        print(f"  平均每次提交改动：{cc.get('avg_lines_per_commit', 0):.1f} 行")
        print(f"  最大单次提交：+{format_number(cc.get('max_commit_added', 0))} / -{format_number(cc.get('max_commit_deleted', 0))}（{cc.get('max_commit_author', '-')}，{cc.get('max_commit_date', '-')}）")
        if cc.get("max_commit_subject"):
            print(f"    提交说明：{cc.get('max_commit_subject')}")
        print(f"  改动文件次数：{format_number(cc.get('total_files_changed', 0))}（去重 {format_number(cc.get('unique_files', 0))} 个文件）")
        print(f"  大型提交（>500 行）：{cc.get('large_commits', 0)} 次")
        print(f"  空提交（无代码改动）：{cc.get('empty_commits', 0)} 次")
        print(f"  代码周转比：{cc.get('churn_ratio', 0):.1f}%（删除 / 总改动）")
        print()

    if cc.get("top_files"):
        print("热点文件 Top 10（改动最频繁）")
        file_rows = [[f["file"], format_number(f["changes"]), format_number(f["added"]), format_number(f["deleted"])] for f in cc["top_files"]]
        print_rows(["文件", "改动次数", "新增", "删除"], file_rows)
        print()

    if cn:
        print("开发者贡献集中度")
        print(f"  Top 1 占比：{cn.get('top1_ratio', 0):.1f}%")
        print(f"  Top 2 占比：{cn.get('top2_ratio', 0):.1f}%")
        print(f"  基尼系数：{cn.get('gini', 0):.2f}（0 均衡，越接近 1 越集中）")
        print(f"  Bus Factor：{cn.get('bus_factor', 0)} 人（贡献 50% 提交所需人数）")
        print(f"  帕累托 80%：{cn.get('pareto_80', 0)} 人（贡献 80% 提交所需人数）")
        print()

    if th:
        print("时间健康度")
        print(f"  深夜提交（22:00-05:00）：{format_number(th.get('night_commits', 0))} 次（{th.get('night_ratio', 0):.1f}%）")
        print(f"  周末提交（周六/日）：{format_number(th.get('weekend_commits', 0))} 次（{th.get('weekend_ratio', 0):.1f}%）")
        print(f"  工作时间（09:00-18:00）：{format_number(th.get('worktime_commits', 0))} 次（{th.get('worktime_ratio', 0):.1f}%）")
        print(f"  非工作时间：{format_number(th.get('offhours_commits', 0))} 次（{th.get('offhours_ratio', 0):.1f}%）")
        print()

    if wc:
        print("工作类型分布（按提交说明关键词）")
        print(f"  Bug 修复：{format_number(wc.get('bug_fix_commits', 0))} 次（{wc.get('bug_fix_ratio', 0):.1f}%）")
        print(f"  重构优化：{format_number(wc.get('refactor_commits', 0))} 次（{wc.get('refactor_ratio', 0):.1f}%）")
        print(f"  其他：{format_number(wc.get('other_commits', 0))} 次（{wc.get('other_ratio', 0):.1f}%）")
        print()

    if cq:
        print("提交质量")
        print(f"  合并提交：{format_number(cq.get('merge_commits', 0))} 次（{cq.get('merge_ratio', 0):.1f}%）")
        print(f"  自动化/Bot 提交：{format_number(cq.get('bot_commits', 0))} 次")
        print(f"  提交说明平均长度：{cq.get('avg_subject_length', 0):.1f} 字 / {cq.get('avg_subject_words', 0):.1f} 词")
        print()

    ma = metrics.get("merge_analysis") or {}
    if ma.get("total_merges"):
        print("合并分析")
        print(f"  合并提交总数：{format_number(ma.get('total_merges', 0))} 次（占全部提交 {ma.get('merge_ratio', 0):.1f}%）")
        print(f"  PR 合并：{format_number(ma.get('pr_merges', 0))} 次 / 分支合并：{format_number(ma.get('branch_merges', 0))} 次")
        if ma.get("merge_by_author"):
            print("  谁做的合并：")
            for row in ma["merge_by_author"]:
                print(f"    {row['author']}：{format_number(row['count'])} 次")
        if ma.get("merge_sources"):
            print("  合并来源分支 Top：")
            for row in ma["merge_sources"]:
                print(f"    {row['branch']}：{format_number(row['count'])} 次")
        print(f"  含冲突解决的合并：{format_number(ma.get('conflict_merges', 0))} 次（占合并 {ma.get('conflict_ratio', 0):.1f}%）")
        if ma.get("conflict_resolvers"):
            print("  谁解决的冲突：")
            for row in ma["conflict_resolvers"]:
                print(f"    {row['author']}：{format_number(row['count'])} 次")
        if ma.get("conflict_files"):
            print("  冲突热点文件：")
            for row in ma["conflict_files"]:
                print(f"    {row['file']}：{format_number(row['count'])} 次")
        print()

    ra = metrics.get("revert_analysis") or {}
    if ra.get("revert_commits") or ra.get("bug_prone_files"):
        print("问题溯源（Revert / Bug 高发）")
        print(f"  回滚提交：{format_number(ra.get('revert_commits', 0))} 次（{ra.get('revert_ratio', 0):.1f}%）")
        if ra.get("revert_by_author"):
            print("  谁在回滚救火：")
            for row in ra["revert_by_author"]:
                print(f"    {row['author']}：{format_number(row['count'])} 次")
        if ra.get("reverted_authors"):
            print("  谁的提交被回滚：")
            for row in ra["reverted_authors"]:
                print(f"    {row['author']}：{format_number(row['count'])} 次")
        if ra.get("bug_prone_files"):
            print("  Bug 高发文件（被修复提交触碰最多）：")
            for row in ra["bug_prone_files"]:
                print(f"    {row['file']}：{format_number(row['count'])} 次")
        print()

    ct = metrics.get("commit_types") or {}
    if ct.get("distribution"):
        print("提交类型细分（Conventional Commits）")
        type_labels = {"feat": "新功能", "fix": "修复", "refactor": "重构", "docs": "文档", "test": "测试", "style": "样式", "perf": "性能", "build": "构建", "ci": "CI", "chore": "杂务", "revert": "回滚", "merge": "合并", "other": "其他"}
        dist_rows = [[type_labels.get(d["type"], d["type"]), format_number(d["count"]), f"{d['ratio']:.1f}%"] for d in ct["distribution"]]
        print_rows(["类型", "提交", "占比"], dist_rows)
        if ct.get("by_author"):
            print("  每位开发者的类型构成：")
            for row in ct["by_author"]:
                parts = [f"{type_labels.get(t, t)} {row[t]}" for t in ("feat", "fix", "refactor", "docs", "test", "chore", "merge", "revert", "other") if row.get(t)]
                print(f"    {row['author']}：{'，'.join(parts) if parts else '无'}")
        print()

    ow = metrics.get("ownership") or {}
    if ow.get("total_files"):
        print("文件所有权与协作")
        print(f"  涉及文件：{format_number(ow.get('total_files', 0))} 个")
        print(f"  单人文件（知识孤岛）：{format_number(ow.get('single_owner_files', 0))} 个（{ow.get('single_owner_ratio', 0):.1f}%）")
        print(f"  多人协作文件：{format_number(ow.get('shared_files', 0))} 个")
        if ow.get("file_owners"):
            print("  热点文件主要负责人：")
            owner_rows = [[f["file"], f["owner"], f"{f['owner_ratio']:.0f}%", f["author_count"]] for f in ow["file_owners"]]
            print_rows(["文件", "主要负责人", "占比", "参与人数"], owner_rows)
        if ow.get("collaboration_pairs"):
            print("  协作最多的搭档（共同改动文件数）：")
            for row in ow["collaboration_pairs"]:
                print(f"    {row['pair']}：{format_number(row['count'])} 个文件")
        print()

    if metrics.get("authors"):
        print("开发者明细")
        author_rows = [[a["author"], format_number(a["commits"]), f"{a['commit_ratio']:.1f}%", format_number(a["added"]), format_number(a["deleted"]), a["active_days"], a["first_commit"], a["last_commit"], a["peak_hour"], f"{a['avg_per_active_day']:.1f}"] for a in metrics["authors"]]
        print_rows(["开发者", "提交", "占比", "新增", "删除", "活跃天", "首提交", "末提交", "最活跃时段", "日均"], author_rows)
        print()

    if metrics.get("projects"):
        print("项目明细")
        project_rows = [[p["project"], format_number(p["commits"]), format_number(p["added"]), format_number(p["deleted"]), p["authors"], p["active_days"]] for p in metrics["projects"]]
        print_rows(["项目", "提交", "新增", "删除", "开发者", "活跃天"], project_rows)
        print()


def print_terminal_report(payload):
    commits = payload["commits"]
    default_filter = payload["default_filter"]
    total_added = sum(commit["added"] for commit in commits)
    total_deleted = sum(commit["deleted"] for commit in commits)
    total_net = total_added - total_deleted
    days = date_diff_days(default_filter["start_date"], default_filter["end_date"])
    work_days, total_hours = estimate_hours(commits)
    daily_commits = len(commits) / days
    daily_hours = total_hours / work_days if work_days else 0
    weekly_hours = daily_hours * 5
    overtime_hours = max(weekly_hours - 40, 0)
    overtime_ratio = overtime_hours / weekly_hours * 100 if weekly_hours else 0

    print()
    print("Git 工作量报告")
    print("=" * 40)
    print(f"统计时间范围：{default_filter['start_date']} 至 {default_filter['end_date']}")
    if default_filter["author_keyword"]:
        print(f"作者关键词：{default_filter['author_keyword']}")
    print(f"生成时间：{payload['generated_at']}")
    print()

    print("核心汇总")
    print(f"  仓库数量：{format_number(len(payload['projects']))}")
    print(f"  有提交项目数：{format_number(len(payload['active_projects']))}")
    print(f"  开发者数量：{format_number(len(payload['authors']))}")
    print(f"  提交次数：{format_number(len(commits))}")
    print(f"  新增代码行：{format_number(total_added)}")
    print(f"  删除代码行：{format_number(total_deleted)}")
    print(f"  净变化行数：{format_number(total_net)}")
    print(f"  日均提交次数：{daily_commits:.1f}")
    print(f"  日均工作时长：{daily_hours:.1f}h")
    print(f"  每周工作时长：{weekly_hours:.1f}h")
    print(f"  加班时间占比：{overtime_ratio:.1f}%")
    print()

    print("项目清单")
    project_counts = group_count(commits, "project")
    project_rows = []
    for repo in payload["repos"]:
        project_rows.append([repo["name"], repo["branch"], format_number(project_counts.get(repo["name"], 0)), repo["path"]])
    print_rows(["项目", "分支", "提交", "路径"], project_rows)
    print()

    print("开发者工作量")
    author_rows = []
    author_map = {}
    for commit in commits:
        author = commit["author"]
        if author not in author_map:
            author_map[author] = {"commits": 0, "added": 0, "deleted": 0, "dates": set()}
        row = author_map[author]
        row["commits"] += 1
        row["added"] += commit["added"]
        row["deleted"] += commit["deleted"]
        row["dates"].add(commit["date"])
    for author, row in sorted(author_map.items(), key=lambda item: item[1]["commits"], reverse=True):
        author_rows.append([
            author,
            format_number(row["commits"]),
            format_number(row["added"]),
            format_number(row["deleted"]),
            format_number(len(row["dates"])),
        ])
    print_rows(["开发者", "提交", "新增", "删除", "工作天数"], author_rows)
    print()

    print("一周七天提交分布")
    week_labels = {"1": "周一", "2": "周二", "3": "周三", "4": "周四", "5": "周五", "6": "周六", "7": "周日"}
    week_counts = group_count(commits, "week_day", ["1", "2", "3", "4", "5", "6", "7"])
    print_rows(["星期", "提交"], [[week_labels[key], format_number(value)] for key, value in week_counts.items()])
    print()

    print("24 小时提交分布")
    hour_counts = group_count(commits, "hour", [str(index).zfill(2) for index in range(24)])
    print_rows(["时间", "提交"], [[f"{key}:00", format_number(value)] for key, value in hour_counts.items()])
    print()

    print_metrics_terminal(payload["metrics"])
    print_branch_overview(payload.get("branch_infos") or [])

    if payload["errors"]:
        print("部分项目读取失败")
        for error in payload["errors"]:
            print(f"  - {error['project']}: {error['message']}")
        print()

def build_project_export_rows(commits):
    rows = {}
    for commit in commits:
        project = commit["project"]
        if project not in rows:
            rows[project] = {
                "project": project,
                "total_lines": 0,
                "added": 0,
                "deleted": 0,
                "commit_count": 0,
                "authors": set(),
            }
        row = rows[project]
        row["total_lines"] += commit["added"] + commit["deleted"]
        row["added"] += commit["added"]
        row["deleted"] += commit["deleted"]
        row["commit_count"] += 1
        row["authors"].add(commit["author"])

    result = []
    for row in rows.values():
        author_count = len(row["authors"])
        result.append({
            "project": row["project"],
            "total_lines": row["total_lines"],
            "added": row["added"],
            "deleted": row["deleted"],
            "commit_count": row["commit_count"],
            "author_count": author_count,
            "per_author_lines": f"{(row['total_lines'] / author_count) if author_count else 0:.2f}",
        })
    return sorted(result, key=lambda item: item["total_lines"], reverse=True)

def parse_mr_ids(subject):
    import re
    return sorted(set(re.findall(r"(?:!|#)(\d+)", str(subject or ""))))

def is_merge_commit(commit):
    return bool(commit.get("is_merge")) or str(commit.get("subject", "")).lower().startswith("merge")

def build_author_export_rows_from_payload(payload):
    commits = payload["commits"]
    default_filter = payload["default_filter"]
    pull_requests = payload.get("pull_requests", [])
    row_map = {}
    for commit in commits:
        key = (commit["project"], commit["author"])
        if key not in row_map:
            row_map[key] = {
                "project": commit["project"],
                "author": commit["author"],
                "total_lines": 0,
                "added": 0,
                "deleted": 0,
                "commit_count": 0,
            }
        row = row_map[key]
        row["total_lines"] += commit["added"] + commit["deleted"]
        row["added"] += commit["added"]
        row["deleted"] += commit["deleted"]
        row["commit_count"] += 1

    result = []
    for row in row_map.values():
        submitted_prs = [
            pr for pr in pull_requests
            if pr["project"] == row["project"]
            and pr["author"] == row["author"]
            and default_filter["start_date"] <= pr["created_at"][:10] <= default_filter["end_date"]
        ]
        merged_pr_count = sum(1 for pr in submitted_prs if pr.get("merged_at"))
        review_pass_rate = merged_pr_count / len(submitted_prs) if submitted_prs else None
        result.append({
            **row,
            "review_pass_rate": review_pass_rate,
        })
    return sorted(result, key=lambda item: (-item["total_lines"], item["author"]))

def format_review_pass_rate(value):
    if value is None:
        return "--"
    return f"{value * 100:.2f}%"

def write_csv_report(payload):
    """导出 CSV。所有指标均直接来自 payload['metrics']（与 Web 报告页同一份核心计算 C），
    保证 CSV 与 Web 内容一致；改一次 C，两处一起更新。"""
    file_name = datetime.now().strftime("output_%Y%m%d%H%M.csv")
    output_file_path = os.path.join(os.getcwd(), file_name)
    project_rows = build_project_export_rows(payload["commits"])
    author_rows = build_author_export_rows_from_payload(payload)
    metrics = payload.get("metrics") or {}
    default_filter = payload["default_filter"]

    def kv(writer, title, pairs):
        writer.writerow([title])
        for name, value in pairs:
            writer.writerow([name, value])
        writer.writerow([])

    def table(writer, title, headers, rows):
        writer.writerow([title])
        writer.writerow(headers)
        for row in rows:
            writer.writerow(row)
        writer.writerow([])

    with open(output_file_path, "w", encoding="utf-8-sig", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["统计维度", "开始时间", default_filter["start_date"], "结束时间", default_filter["end_date"]])
        writer.writerow([])

        # 核心汇总（与 Web 核心汇总同源，来自 payload）
        commits = payload["commits"]
        total_added = sum(c["added"] for c in commits)
        total_deleted = sum(c["deleted"] for c in commits)
        kv(writer, "核心汇总", [
            ("仓库数量", len(payload.get("projects", []))),
            ("有提交项目数", len(payload.get("active_projects", []))),
            ("开发者数量", len(payload.get("authors", []))),
            ("提交次数", len(commits)),
            ("新增代码行", total_added),
            ("删除代码行", total_deleted),
            ("净变化行数", total_added - total_deleted),
        ])

        # 项目维度（保留原有汇总，含人均代码行）
        writer.writerow(["项目维度"])
        writer.writerow(["项目名称", "代码总行数", "新增行数", "删除行数", "提交代码总行数", "提交次数", "人均代码行数"])
        for row in project_rows:
            writer.writerow([
                row["project"],
                row["total_lines"],
                row["added"],
                row["deleted"],
                row["total_lines"],
                row["commit_count"],
                row["per_author_lines"],
            ])
        writer.writerow([])

        # 人员维度（保留原有汇总，含代码审核合格率）
        writer.writerow(["人员维度"])
        writer.writerow(["项目名称", "姓名", "提交总代码行", "新增行数", "删除行数", "提交次数", "代码审核合格率"])
        for row in author_rows:
            writer.writerow([
                row["project"],
                row["author"],
                row["total_lines"],
                row["added"],
                row["deleted"],
                row["commit_count"],
                format_review_pass_rate(row["review_pass_rate"]),
            ])
        writer.writerow([])

        # ===== 以下全部来自 payload['metrics']，与 Web 报告页同一份核心计算 C =====
        ts = metrics.get("time_span") or {}
        if ts:
            kv(writer, "时间跨度与活跃度", [
                ("首次提交", ts.get("first_commit_date", "-")),
                ("最近提交", ts.get("last_commit_date", "-")),
                ("时间跨度(天)", ts.get("span_days", 0)),
                ("活跃天数", ts.get("active_days", 0)),
                ("活跃密度(%)", f'{ts.get("active_day_ratio", 0):.1f}'),
            ])

        cd = metrics.get("cadence") or {}
        if cd:
            kv(writer, "提交节奏", [
                ("最忙一天", cd.get("peak_day_date", "-")),
                ("最忙日提交数", cd.get("max_commits_in_one_day", 0)),
                ("提交尖峰(x)", f'{cd.get("commit_spike", 0):.1f}'),
                ("最长连续提交(天)", cd.get("longest_streak", 0)),
                ("当前连续提交(天)", cd.get("current_streak", 0)),
                ("平均提交间隔(分钟)", f'{cd.get("avg_interval_minutes", 0):.0f}'),
                ("最活跃星期", cd.get("peak_weekday", "-")),
                ("最活跃时段", cd.get("peak_hour", "-")),
            ])

        mt = metrics.get("monthly_trend") or []
        if mt:
            table(writer, "月度提交趋势", ["月份", "提交", "新增", "删除", "开发者", "活跃天"],
                [[m["month"], m["commits"], m["added"], m["deleted"], m["authors"], m["active_days"]] for m in mt])

        cc = metrics.get("code_changes") or {}
        if cc:
            kv(writer, "代码改动概览", [
                ("平均每次提交改动", f'{cc.get("avg_lines_per_commit", 0):.1f}'),
                ("最大单次新增", cc.get("max_commit_added", 0)),
                ("最大单次删除", cc.get("max_commit_deleted", 0)),
                ("最大单次作者", cc.get("max_commit_author", "-")),
                ("改动文件次数", cc.get("total_files_changed", 0)),
                ("去重文件数", cc.get("unique_files", 0)),
                ("大型提交(>500行)", cc.get("large_commits", 0)),
                ("空提交", cc.get("empty_commits", 0)),
                ("代码周转比(%)", f'{cc.get("churn_ratio", 0):.1f}'),
            ])
            top_files = cc.get("top_files") or []
            if top_files:
                table(writer, "热点文件 Top10", ["文件", "改动次数", "新增", "删除"],
                    [[f["file"], f["changes"], f["added"], f["deleted"]] for f in top_files])

        cn = metrics.get("concentration") or {}
        if cn:
            kv(writer, "开发者贡献集中度", [
                ("Top1占比(%)", f'{cn.get("top1_ratio", 0):.1f}'),
                ("Top2占比(%)", f'{cn.get("top2_ratio", 0):.1f}'),
                ("基尼系数", f'{cn.get("gini", 0):.2f}'),
                ("Bus Factor(人)", cn.get("bus_factor", 0)),
                ("帕累托80%(人)", cn.get("pareto_80", 0)),
            ])

        th = metrics.get("time_health") or {}
        if th:
            kv(writer, "时间健康度", [
                ("深夜提交(22:00-05:00)", f'{th.get("night_commits", 0)} ({th.get("night_ratio", 0):.1f}%)'),
                ("周末提交(周六/日)", f'{th.get("weekend_commits", 0)} ({th.get("weekend_ratio", 0):.1f}%)'),
                ("工作时间(09:00-18:00)", f'{th.get("worktime_commits", 0)} ({th.get("worktime_ratio", 0):.1f}%)'),
                ("非工作时间", f'{th.get("offhours_commits", 0)} ({th.get("offhours_ratio", 0):.1f}%)'),
            ])

        wc = metrics.get("work_categories") or {}
        if wc:
            kv(writer, "工作类型分布(按提交说明关键词)", [
                ("Bug修复", f'{wc.get("bug_fix_commits", 0)} ({wc.get("bug_fix_ratio", 0):.1f}%)'),
                ("重构优化", f'{wc.get("refactor_commits", 0)} ({wc.get("refactor_ratio", 0):.1f}%)'),
                ("其他", f'{wc.get("other_commits", 0)} ({wc.get("other_ratio", 0):.1f}%)'),
            ])

        cq = metrics.get("commit_quality") or {}
        if cq:
            kv(writer, "提交质量", [
                ("合并提交", f'{cq.get("merge_commits", 0)} ({cq.get("merge_ratio", 0):.1f}%)'),
                ("自动化/Bot提交", cq.get("bot_commits", 0)),
                ("提交说明平均长度(字)", f'{cq.get("avg_subject_length", 0):.1f}'),
                ("提交说明平均词数", f'{cq.get("avg_subject_words", 0):.1f}'),
            ])

        ma = metrics.get("merge_analysis") or {}
        if ma.get("total_merges"):
            kv(writer, "合并分析", [
                ("合并提交总数", f'{ma.get("total_merges", 0)} ({ma.get("merge_ratio", 0):.1f}%)'),
                ("PR合并", ma.get("pr_merges", 0)),
                ("分支合并", ma.get("branch_merges", 0)),
                ("含冲突解决的合并", f'{ma.get("conflict_merges", 0)} ({ma.get("conflict_ratio", 0):.1f}%)'),
            ])
            if ma.get("merge_by_author"):
                table(writer, "谁做的合并", ["作者", "次数"], [[r["author"], r["count"]] for r in ma["merge_by_author"]])
            if ma.get("merge_sources"):
                table(writer, "合并来源分支 Top", ["分支", "次数"], [[r["branch"], r["count"]] for r in ma["merge_sources"]])
            if ma.get("conflict_resolvers"):
                table(writer, "谁解决的冲突", ["作者", "次数"], [[r["author"], r["count"]] for r in ma["conflict_resolvers"]])
            if ma.get("conflict_files"):
                table(writer, "冲突热点文件", ["文件", "次数"], [[r["file"], r["count"]] for r in ma["conflict_files"]])

        ra = metrics.get("revert_analysis") or {}
        if ra.get("revert_commits") or ra.get("bug_prone_files"):
            kv(writer, "问题溯源(Revert/Bug高发)", [
                ("回滚提交", f'{ra.get("revert_commits", 0)} ({ra.get("revert_ratio", 0):.1f}%)'),
            ])
            if ra.get("revert_by_author"):
                table(writer, "谁在回滚救火", ["作者", "次数"], [[r["author"], r["count"]] for r in ra["revert_by_author"]])
            if ra.get("reverted_authors"):
                table(writer, "谁的提交被回滚", ["作者", "次数"], [[r["author"], r["count"]] for r in ra["reverted_authors"]])
            if ra.get("bug_prone_files"):
                table(writer, "Bug高发文件", ["文件", "次数"], [[r["file"], r["count"]] for r in ra["bug_prone_files"]])

        ct = metrics.get("commit_types") or {}
        if ct.get("distribution"):
            table(writer, "提交类型细分", ["类型", "提交", "占比%"],
                [[d["type"], d["count"], f'{d["ratio"]:.1f}'] for d in ct["distribution"]])
            if ct.get("by_author"):
                type_cols = ["feat", "fix", "refactor", "docs", "test", "style", "perf", "build", "ci", "chore", "revert", "merge", "other"]
                table(writer, "每位开发者提交类型构成", ["开发者"] + type_cols,
                    [[r["author"]] + [r.get(t, 0) for t in type_cols] for r in ct["by_author"]])

        ow = metrics.get("ownership") or {}
        if ow.get("total_files"):
            kv(writer, "文件所有权与协作", [
                ("涉及文件", ow.get("total_files", 0)),
                ("单人文件(知识孤岛)", f'{ow.get("single_owner_files", 0)} ({ow.get("single_owner_ratio", 0):.1f}%)'),
                ("多人协作文件", ow.get("shared_files", 0)),
            ])
            if ow.get("file_owners"):
                table(writer, "热点文件主要负责人", ["文件", "主要负责人", "占比%", "参与人数"],
                    [[f["file"], f["owner"], f'{f["owner_ratio"]:.0f}', f["author_count"]] for f in ow["file_owners"]])
            if ow.get("collaboration_pairs"):
                table(writer, "协作最多的搭档", ["搭档", "共同改动文件数"],
                    [[r["pair"], r["count"]] for r in ow["collaboration_pairs"]])
    return output_file_path

def escape_xml(value):
    return (
        str(value)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )

def string_cell(ref, value, style_index):
    return f'<c r="{ref}" s="{style_index}" t="inlineStr"><is><t>{escape_xml(value)}</t></is></c>'

def number_cell(ref, value, style_index):
    return f'<c r="{ref}" s="{style_index}"><v>{value}</v></c>'

def empty_cell(ref, style_index):
    return f'<c r="{ref}" s="{style_index}"/>'

def percent_cell(ref, value, style_index):
    return f'<c r="{ref}" s="{style_index}"><v>{value}</v></c>'

def build_project_sheet_xml(payload):
    commits = payload["commits"]
    default_filter = payload["default_filter"]
    project_rows = build_project_export_rows(commits)
    total_rows = max(len(project_rows), 2)
    rows = []

    rows.append(
        '<row r="1">'
        + string_cell("A1", "时间：", 6)
        + string_cell("B1", "开始时间", 7)
        + string_cell("C1", default_filter["start_date"], 8)
        + string_cell("D1", "结束时间", 7)
        + string_cell("E1", default_filter["end_date"], 8)
        + empty_cell("F1", 8)
        + empty_cell("G1", 8)
        + "</row>"
    )
    rows.append(
        '<row r="2">'
        + string_cell("A2", "项目代码变化情况", 3)
        + empty_cell("B2", 4)
        + empty_cell("C2", 4)
        + empty_cell("D2", 5)
        + string_cell("E2", "人均提交代码变化", 3)
        + empty_cell("F2", 4)
        + empty_cell("G2", 5)
        + "</row>"
    )
    rows.append(
        '<row r="3">'
        + string_cell("A3", "项目名称", 1)
        + string_cell("B3", "代码总行数", 1)
        + string_cell("C3", "新增行数", 1)
        + string_cell("D3", "删除行数", 1)
        + string_cell("E3", "提交代码总行数", 1)
        + string_cell("F3", "提交次数", 1)
        + string_cell("G3", "人均代码行数", 1)
        + "</row>"
    )

    for index in range(total_rows):
        row_number = index + 4
        row = project_rows[index] if index < len(project_rows) else None
        row_xml = [f'<row r="{row_number}">']
        row_xml.append(string_cell(f"A{row_number}", row["project"] if row else "", 2))
        row_xml.append(number_cell(f"B{row_number}", row["total_lines"], 2) if row else empty_cell(f"B{row_number}", 2))
        row_xml.append(number_cell(f"C{row_number}", row["added"], 2) if row else empty_cell(f"C{row_number}", 2))
        row_xml.append(number_cell(f"D{row_number}", row["deleted"], 2) if row else empty_cell(f"D{row_number}", 2))
        row_xml.append(number_cell(f"E{row_number}", row["total_lines"], 2) if row else empty_cell(f"E{row_number}", 2))
        row_xml.append(number_cell(f"F{row_number}", row["commit_count"], 2) if row else empty_cell(f"F{row_number}", 2))
        row_xml.append(number_cell(f"G{row_number}", row["per_author_lines"], 2) if row else empty_cell(f"G{row_number}", 2))
        row_xml.append("</row>")
        rows.append("".join(row_xml))

    last_row = total_rows + 3
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1:G{last_row}"/>
  <sheetViews>
    <sheetView tabSelected="1" workbookViewId="0"/>
  </sheetViews>
  <sheetFormatPr defaultRowHeight="18"/>
  <cols>
    <col min="1" max="1" width="24" customWidth="1"/>
    <col min="2" max="2" width="18" customWidth="1"/>
    <col min="3" max="4" width="16" customWidth="1"/>
    <col min="5" max="6" width="18" customWidth="1"/>
    <col min="7" max="7" width="22" customWidth="1"/>
  </cols>
  <sheetData>
    {''.join(rows)}
  </sheetData>
  <mergeCells count="2">
    <mergeCell ref="A2:D2"/>
    <mergeCell ref="E2:G2"/>
  </mergeCells>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>"""

def build_author_sheet_xml(payload):
    commits = payload["commits"]
    default_filter = payload["default_filter"]
    author_rows = build_author_export_rows_from_payload(payload)
    total_rows = max(len(author_rows), 1)
    rows = []

    rows.append(
        '<row r="1">'
        + string_cell("A1", "时间：", 6)
        + string_cell("B1", "开始时间", 7)
        + string_cell("C1", default_filter["start_date"], 8)
        + string_cell("D1", "结束时间", 7)
        + string_cell("E1", default_filter["end_date"], 8)
        + empty_cell("F1", 8)
        + empty_cell("G1", 8)
        + "</row>"
    )
    rows.append(
        '<row r="2">'
        + string_cell("A2", "项目名称", 1)
        + string_cell("B2", "姓名", 1)
        + string_cell("C2", "提交总代码行", 1)
        + string_cell("D2", "新增行数", 1)
        + string_cell("E2", "删除行数", 1)
        + string_cell("F2", "提交次数", 1)
        + string_cell("G2", "代码审核合格率", 1)
        + "</row>"
    )

    for index in range(total_rows):
        row_number = index + 3
        row = author_rows[index] if index < len(author_rows) else None
        row_xml = [f'<row r="{row_number}">']
        row_xml.append(string_cell(f"A{row_number}", row["project"] if row else "", 2))
        row_xml.append(string_cell(f"B{row_number}", row["author"] if row else "", 2))
        row_xml.append(number_cell(f"C{row_number}", row["total_lines"], 2) if row else empty_cell(f"C{row_number}", 2))
        row_xml.append(number_cell(f"D{row_number}", row["added"], 2) if row else empty_cell(f"D{row_number}", 2))
        row_xml.append(number_cell(f"E{row_number}", row["deleted"], 2) if row else empty_cell(f"E{row_number}", 2))
        row_xml.append(number_cell(f"F{row_number}", row["commit_count"], 2) if row else empty_cell(f"F{row_number}", 2))
        if row:
            if row["review_pass_rate"] is None:
                row_xml.append(string_cell(f"G{row_number}", "--", 2))
            else:
                row_xml.append(percent_cell(f"G{row_number}", row["review_pass_rate"], 9))
        else:
            row_xml.append(empty_cell(f"G{row_number}", 2))
        row_xml.append("</row>")
        rows.append("".join(row_xml))

    last_row = total_rows + 2
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1:G{last_row}"/>
  <sheetViews>
    <sheetView workbookViewId="0"/>
  </sheetViews>
  <sheetFormatPr defaultRowHeight="18"/>
  <cols>
    <col min="1" max="1" width="14" customWidth="1"/>
    <col min="2" max="2" width="14" customWidth="1"/>
    <col min="3" max="3" width="16" customWidth="1"/>
    <col min="4" max="4" width="16" customWidth="1"/>
    <col min="5" max="5" width="14" customWidth="1"/>
    <col min="6" max="6" width="14.9" customWidth="1"/>
    <col min="7" max="7" width="20.3" customWidth="1"/>
  </cols>
  <sheetData>
    {''.join(rows)}
  </sheetData>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>"""

def build_xlsx_styles_xml():
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1">
    <numFmt numFmtId="164" formatCode="0.00%"/>
  </numFmts>
  <fonts count="2">
    <font><sz val="11"/><name val="微软雅黑"/></font>
    <font><b/><sz val="11"/><name val="微软雅黑"/></font>
  </fonts>
  <fills count="4">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFDBEAFE"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFEFF6FF"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFD9E2EC"/></left>
      <right style="thin"><color rgb="FFD9E2EC"/></right>
      <top style="thin"><color rgb="FFD9E2EC"/></top>
      <bottom style="thin"><color rgb="FFD9E2EC"/></bottom>
      <diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="10">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="常规" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>"""

def write_xlsx_report(payload):
    file_name = datetime.now().strftime("output_%Y%m%d%H%M.xlsx")
    output_file_path = os.path.join(os.getcwd(), file_name)
    files = {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>""",
        "_rels/.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>""",
        "docProps/app.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>git-workload-report</Application>
  <HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>工作表</vt:lpstr></vt:variant><vt:variant><vt:i4>2</vt:i4></vt:variant></vt:vector></HeadingPairs>
  <TitlesOfParts><vt:vector size="2" baseType="lpstr"><vt:lpstr>Sheet1</vt:lpstr><vt:lpstr>Sheet2</vt:lpstr></vt:vector></TitlesOfParts>
</Properties>""",
        "docProps/core.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:creator>git-workload-report</dc:creator>
  <cp:lastModifiedBy>git-workload-report</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{datetime.now().isoformat()}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{datetime.now().isoformat()}</dcterms:modified>
</cp:coreProperties>""",
        "xl/workbook.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
    <sheet name="Sheet2" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>""",
        "xl/_rels/workbook.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>""",
        "xl/styles.xml": build_xlsx_styles_xml(),
        "xl/worksheets/sheet1.xml": build_project_sheet_xml(payload),
        "xl/worksheets/sheet2.xml": build_author_sheet_xml(payload),
    }
    with zipfile.ZipFile(output_file_path, "w", compression=zipfile.ZIP_STORED) as archive:
        for path, content in files.items():
            archive.writestr(path, content)
    return output_file_path

def print_web_summary(payload):
    default_filter = payload["default_filter"]
    commits = [
        commit
        for commit in payload["commits"]
        if default_filter["start_date"] <= commit["date"] <= default_filter["end_date"]
    ]
    total_added = sum(commit["added"] for commit in commits)
    total_deleted = sum(commit["deleted"] for commit in commits)
    print(f"统计时间范围：{default_filter['start_date']} 至 {default_filter['end_date']}")
    print(f"仓库数量：{len(payload['projects'])}")
    print(f"有提交项目数：{len({commit['project'] for commit in commits})}")
    print(f"开发者数量：{len({commit['author'] for commit in commits})}")
    print(f"提交次数：{len(commits)}")
    print(f"新增代码行：{total_added}")
    print(f"删除代码行：{total_deleted}")
    if payload["errors"]:
        print("部分项目读取失败：")
        for error in payload["errors"]:
            print(f"  - {error['project']}: {error['message']}")

print_progress(f"统计时间范围：{collect_time_start} 至 {collect_time_end}")
if author_filter:
    print_progress(f"作者关键词：{author_filter}")
repos = discover_repos()
all_commits = []
errors = []
branch_infos = []
conflict_merge_map = {}
for index, repo in enumerate(repos, start=1):
    try:
        print_progress(f"处理仓库 {index}/{len(repos)}")
        all_commits.extend(parse_commits(repo))
        conflict_merge_map.update(collect_conflict_merges(repo))
        branch_infos.append(collect_branches(repo))
    except Exception as exc:
        print_progress(f"仓库读取失败：{os.path.basename(repo)}，{exc}")
        errors.append({"project": os.path.basename(repo), "message": str(exc)})

# 给合并提交补充冲突解决文件（combined diff 有内容 = 该合并动过手）
for commit in all_commits:
    if commit.get("is_merge") and commit["hash"] in conflict_merge_map:
        commit["conflict_files"] = conflict_merge_map[commit["hash"]]

repo_infos = []
for path in repos:
    repo_infos.append({
        "name": os.path.basename(path),
        "branch": git_branch(path),
        "path": path,
        "remote": parse_remote_info(git_remote_url(path), path),
    })
pull_requests = build_pull_requests(repo_infos, all_commits, collect_time_start)
authors = sorted({commit["author"] for commit in all_commits})
projects = sorted({repo["name"] for repo in repo_infos})
active_projects = sorted({commit["project"] for commit in all_commits})
print_progress(f"统计数据汇总完成：{len(projects)} 个仓库，{len(active_projects)} 个有提交项目，{len(authors)} 位开发者，{len(all_commits)} 次提交")
payload = {
    "generated_at": datetime.now().isoformat(timespec="seconds"),
    "default_filter": {
        "start_date": default_filter_start,
        "end_date": default_filter_end,
        "author_keyword": author_filter,
    },
    "data_range": {
        "start_date": collect_time_start,
        "end_date": collect_time_end,
    },
    "projects": projects,
    "active_projects": active_projects,
    "authors": authors,
    "repos": [{"name": repo["name"], "branch": repo["branch"], "path": repo["path"]} for repo in repo_infos],
    "commits": all_commits,
    "pull_requests": pull_requests,
    "branch_infos": branch_infos,
    "metrics": build_metrics(all_commits),
    "errors": errors,
}
with open(output_path, "w", encoding="utf-8") as file:
    json.dump(payload, file, ensure_ascii=False)
print_progress(f"报告数据已生成：{output_path}")

if report_mode == "web":
    print_web_summary(payload)
else:
    print_terminal_report(payload)
    export_path = write_csv_report(payload)
    print()
    print(f"CSV 报告已导出：{export_path}")
    print(f"统计时间范围：{payload['default_filter']['start_date']} 至 {payload['default_filter']['end_date']}")
    print(f"仓库数量：{len(payload['projects'])}")
    print(f"有提交项目数：{len(payload['active_projects'])}")
    print(f"开发者数量：{len(payload['authors'])}")
    print(f"提交次数：{len(payload['commits'])}")
    if payload["errors"]:
        print("部分项目读取失败：")
        for error in payload["errors"]:
            print(f"  - {error['project']}: {error['message']}")
PY

if [ "$report_mode" != "web" ]
then
    rm -rf "$work_dir"
    exit 0
fi

find_free_port()
{
python3 - "$1" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, start + 100):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        break
PY
}

# find_free_port 只是探测，探完就把端口放开了，到真正监听之间存在时间差，
# 这段时间里端口可能被别的进程抢走。所以这里必须确认服务真的能连上，不能只看进程起没起。
wait_for_local_port()
{
python3 - "$1" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.time() + 3
while time.time() < deadline:
    sock = socket.socket()
    sock.settimeout(0.5)
    connected = sock.connect_ex(("127.0.0.1", port)) == 0
    sock.close()
    if connected:
        sys.exit(0)
    time.sleep(0.2)
sys.exit(1)
PY
}

# Web 模式的本地服务必须是当前终端的前台子进程，不允许脱离会话在后台常驻。
# 语义是：命令跑完终端就一直占着，谁关终端谁停服务；按 Ctrl+C 才释放端口并删掉临时目录。
# 这样用户不会留下一堆自己都不知道的孤儿服务，也不用再手动记 PID 去 kill。
# 访问日志直接丢弃，保持控制台干净，只留“运行中”这一个状态。
# 起不来就换端口重试，最多 3 次；3 次都失败就明确报错退出，绝不打印一个连不上的地址糊弄用户。
server_pid=""
scan_base="${GIT_WORKLOAD_REPORT_PORT:-19960}"
attempt=1
while [ "$attempt" -le 3 ]
do
    port=`find_free_port "$scan_base"`

    if [ -z "$port" ]
    then
        echo "第 $attempt 次尝试：从 $scan_base 起往后 100 个端口都被占用。"
    else
        python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work_dir" >/dev/null 2>&1 &
        candidate_pid=$!

        if wait_for_local_port "$port"
        then
            server_pid="$candidate_pid"
            break
        fi

        kill "$candidate_pid" 2>/dev/null
        wait "$candidate_pid" 2>/dev/null
        echo "第 $attempt 次尝试：端口 $port 上的本地服务没起来，可能刚被其他进程抢占。"
        # 这次没起来，下次从刚失败的端口往后接着找，真正换一个端口试
        scan_base=$((port + 1))
    fi

    attempt=$((attempt + 1))
    sleep 1
done

if [ -z "$server_pid" ]
then
    echo "本地服务连续 3 次启动失败，已放弃。"
    echo "请检查 ${GIT_WORKLOAD_REPORT_PORT:-19960} 起的端口占用：lsof -nP -iTCP -sTCP:LISTEN"
    echo "也可以设置 GIT_WORKLOAD_REPORT_PORT 指定其他起始端口后重试。"
    rm -rf "$work_dir"
    exit 1
fi

# Ctrl+C（INT）、kill（TERM）、关终端（HUP）走同一套收尾：停服务、回收子进程、清临时目录。
# 关终端时 SIGHUP 会打到整个前台进程组，脚本和 http.server 都会收到，这里统一清理，不留目录。
trap 'kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; rm -rf "$work_dir"; echo; echo "本地服务已停止，临时报告目录已清理。"; exit 0' INT TERM HUP

local_url="http://127.0.0.1:$port/"

echo
echo "本地可视化分析结果已启动:"
echo "$local_url"
echo "如需指定端口，可设置环境变量：GIT_WORKLOAD_REPORT_PORT=19960"

if ! open_local_url "$local_url"
then
    echo "未能自动打开浏览器，请手动复制上面的地址访问。"
fi

echo "本地服务运行中，按 Ctrl+C 停止并清理临时报告目录。"
wait "$server_pid"

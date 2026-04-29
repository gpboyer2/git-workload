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
    time_start=$(date -d "$(date "+%Y-%m-%d") -6 day" "+%Y-%m-%d")
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
    return subprocess.check_output(["git", "-C", repo_path, *args], text=True, stderr=subprocess.DEVNULL)

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
    pull_requests = []
    for repo_info in repo_infos:
        if repo_info["remote"]["provider"] != "github":
            continue
        repo_commits = [commit for commit in commits if commit["project_path"] == repo_info["path"]]
        if not repo_commits:
            continue
        author_logins = resolve_github_author_logins(repo_info["remote"], repo_commits)
        login_to_authors = {}
        for author, logins in author_logins.items():
            for login in logins:
                login_to_authors.setdefault(login, set()).add(author)
        if not login_to_authors:
            continue
        print_progress(f'读取 GitHub PR：{repo_info["name"]}')
        pulls = fetch_github_pull_requests(repo_info["remote"], start_date)
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

def build_pull_requests_api(repo_infos, commits, start_date):
    pull_requests = []
    for repo_info in repo_infos:
        remote_info = repo_info["remote"]
        repo_commits = [commit for commit in commits if commit["project_path"] == repo_info["path"]]
        if not repo_commits:
            continue

        login_to_authors = {}
        pulls = []

        if remote_info["provider"] == "gitlab":
            author_logins = resolve_gitlab_author_logins(remote_info, repo_commits)
            for author, logins in author_logins.items():
                for login in logins:
                    login_to_authors.setdefault(login, set()).add(author)
            if not login_to_authors:
                continue
            print_progress(f'读取 GitLab MR：{repo_info["name"]}')
            pulls = fetch_gitlab_merge_requests(remote_info, start_date, login_to_authors.keys())
        elif remote_info["provider"] == "github":
            author_logins = resolve_github_author_logins(remote_info, repo_commits)
            for author, logins in author_logins.items():
                for login in logins:
                    login_to_authors.setdefault(login, set()).add(author)
            if not login_to_authors:
                continue
            print_progress(f'读取 GitHub PR：{repo_info["name"]}')
            pulls = fetch_github_pull_requests(remote_info, start_date)
        else:
            continue

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

def format_number(value):
    return f"{value:,}"

def date_diff_days(start_date, end_date):
    start = datetime.fromisoformat(start_date)
    end = datetime.fromisoformat(end_date)
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
    file_name = datetime.now().strftime("output_%Y%m%d%H%M.csv")
    output_file_path = os.path.join(os.getcwd(), file_name)
    project_rows = build_project_export_rows(payload["commits"])
    author_rows = build_author_export_rows_from_payload(payload)
    default_filter = payload["default_filter"]

    with open(output_file_path, "w", encoding="utf-8-sig", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["统计维度", "开始时间", default_filter["start_date"], "结束时间", default_filter["end_date"]])
        writer.writerow([])
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
    default_filter = payload["default_filter"]
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
for index, repo in enumerate(repos, start=1):
    try:
        print_progress(f"处理仓库 {index}/{len(repos)}")
        all_commits.extend(parse_commits(repo))
    except Exception as exc:
        print_progress(f"仓库读取失败：{os.path.basename(repo)}，{exc}")
        errors.append({"project": os.path.basename(repo), "message": str(exc)})

repo_infos = []
for path in repos:
    repo_infos.append({
        "name": os.path.basename(path),
        "branch": git_branch(path),
        "path": path,
        "remote": parse_remote_info(git_remote_url(path), path),
    })
pull_requests = build_pull_requests_api(repo_infos, all_commits, collect_time_start)
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
    "errors": errors,
}
with open(output_path, "w", encoding="utf-8") as file:
    json.dump(payload, file, ensure_ascii=False)
print_progress(f"报告数据已生成：{output_path}")

if report_mode == "web":
    print_web_summary(payload)
else:
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

port=`find_free_port "${GIT_WORKLOAD_REPORT_PORT:-19960}"`

if [ -z "$port" ]
then
    echo "未找到可用本地端口，请稍后再试。"
    exit 1
fi

server_pid=`python3 - "$port" "$work_dir" "/tmp/git-workload-report-$port.log" <<'PY'
import subprocess
import sys

port, work_dir, log_path = sys.argv[1:]
log_file = open(log_path, "ab")
process = subprocess.Popen(
    [sys.executable, "-m", "http.server", port, "--bind", "127.0.0.1", "--directory", work_dir],
    stdin=subprocess.DEVNULL,
    stdout=log_file,
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
print(process.pid)
PY
`
local_url="http://127.0.0.1:$port/"

echo
echo "本地可视化分析结果已启动:"
echo "$local_url"
echo "本地服务进程：$server_pid"
echo "如需指定端口，可设置环境变量：GIT_WORKLOAD_REPORT_PORT=19960"

if ! open_local_url "$local_url"
then
    echo "未能自动打开浏览器，请手动复制上面的地址访问。"
fi

if [ "$GIT_WORKLOAD_REPORT_KEEP_ALIVE" = "1" ]
then
    echo "dev 模式会保持本地服务运行，按 Ctrl+C 停止。"
    wait "$server_pid"
fi

#!/usr/bin/env bash

set -euo pipefail

version="${VERSION:-}"

if [ -z "$version" ]
then
    version=$(node -e "console.log(require('./package.json').version)")
fi

function tag_exists() {
    local tag_name="$1"
    git rev-parse "$tag_name" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "refs/tags/$tag_name" >/dev/null 2>&1
}

function next_patch_version() {
    node - "$1" <<'NODE'
const version = process.argv[2]
const parts = version.split(".").map(Number)
if (parts.length !== 3 || parts.some((item) => !Number.isInteger(item) || item < 0)) {
  throw new Error(`版本号必须是 x.y.z 格式：${version}`)
}
parts[2] += 1
console.log(parts.join("."))
NODE
}

requested_version="${VERSION:-}"
branch=$(git branch --show-current)
if [ -z "$branch" ]
then
    echo "当前不在普通分支上，无法创建发布 tag。"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]
then
    echo "当前存在未提交变更，GitHub Actions 只能构建已提交并推送到远端的代码。"
    echo "请先提交或处理当前修改后再运行 npm run build-github。"
    exit 1
fi

while tag_exists "v$version"
do
    if [ -n "$requested_version" ]
    then
        echo "指定版本的 tag 已存在：v$version"
        echo "请换一个 VERSION 后再运行。"
        exit 1
    fi
    version=$(next_patch_version "$version")
done

if [ -z "$requested_version" ]
then
    node - "$version" <<'NODE'
const fs = require("fs")
const version = process.argv[2]
function updateJson(filePath, updater) {
  if (!fs.existsSync(filePath)) return
  const data = JSON.parse(fs.readFileSync(filePath, "utf8"))
  updater(data)
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`)
}
updateJson("package.json", (data) => {
  data.version = version
})
updateJson("package-lock.json", (data) => {
  data.version = version
  if (data.packages && data.packages[""]) data.packages[""].version = version
})
NODE
    git add package.json
    if [ -f package-lock.json ]; then git add package-lock.json; fi
    if ! git diff --cached --quiet
    then
        git commit -m "chore: release v$version"
    fi
fi

tag_name="v$version"
git push origin "$branch"
git tag "$tag_name"
git push origin "$tag_name"

echo "已推送 tag，GitHub Actions 会自动触发 Release 构建。"
echo "tag：$tag_name"
echo "版本：$version"

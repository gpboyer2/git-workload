const weekLabels = {
  1: "周一",
  2: "周二",
  3: "周三",
  4: "周四",
  5: "周五",
  6: "周六",
  7: "周日",
}

const periodOptions = [
  { value: "all", label: "全部时间" },
  { value: "this-week", label: "本周" },
  { value: "this-month", label: "本月" },
  { value: "last-7", label: "近 7 天" },
  { value: "last-30", label: "近 30 天" },
  { value: "last-90", label: "近 90 天" },
  { value: "this-year", label: "今年" },
  { value: "custom", label: "自定义" },
]

const chartMap = new Map()

const state = {
  data: null,
  selectedProjects: new Set(),
  selectedAuthors: new Set(),
  period: "all",
}

const dom = {
  reportMeta: document.getElementById("reportMeta"),
  exportCsv: document.getElementById("exportCsv"),
  exportReport: document.getElementById("exportReport"),
  repoInfoList: document.getElementById("repoInfoList"),
  repoMaster: document.getElementById("repoMaster"),
  repoSelectedCount: document.getElementById("repoSelectedCount"),
  repoClearAll: document.getElementById("repoClearAll"),
  repoInvert: document.getElementById("repoInvert"),
  authorChoices: document.getElementById("authorChoices"),
  periodChoices: document.getElementById("periodChoices"),
  dateRangeLabel: document.getElementById("dateRangeLabel"),
  customDateRange: document.getElementById("customDateRange"),
  startDate: document.getElementById("startDate"),
  endDate: document.getElementById("endDate"),
}

const textEncoder = new TextEncoder()

function formatNumber(value) {
  return Number(value || 0).toLocaleString("zh-CN")
}

function uniqueCount(list, selector) {
  return new Set(list.map(selector).filter(Boolean)).size
}

function parseDate(value) {
  const [year, month, day] = value.split("-").map(Number)
  return new Date(year, month - 1, day)
}

function formatDate(date) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

function addDays(value, days) {
  const date = parseDate(value)
  date.setDate(date.getDate() + days)
  return formatDate(date)
}

function clampDate(value, min, max) {
  if (value < min) return min
  if (value > max) return max
  return value
}

function dateDiffDays(startDate, endDate) {
  const start = parseDate(startDate)
  const end = parseDate(endDate)
  const diff = Math.round((end - start) / 86400000) + 1
  return Math.max(diff, 1)
}

function getCssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim()
}

function chartColors() {
  return [
    getCssVar("--color-primary"),
    getCssVar("--color-green"),
    getCssVar("--color-purple"),
    getCssVar("--color-orange"),
    getCssVar("--color-cyan"),
    getCssVar("--color-pink"),
    getCssVar("--color-yellow"),
    getCssVar("--color-red"),
  ]
}

function estimateHours(commits) {
  const byDate = new Map()
  commits.forEach((commit) => {
    if (!byDate.has(commit.date)) byDate.set(commit.date, [])
    byDate.get(commit.date).push(Number(commit.hour))
  })
  let total = 0
  byDate.forEach((hours) => {
    total += Math.max(...hours) - Math.min(...hours) + 1
  })
  return { workDays: byDate.size, totalHours: total }
}

function renderChoices(container, values, selectedSet) {
  container.textContent = ""
  values.forEach((value) => {
    const label = document.createElement("label")
    const input = document.createElement("input")
    input.type = "checkbox"
    input.value = value
    input.checked = selectedSet.has(value)
    label.append(input, value)
    container.append(label)
  })
}

let repoStatsCache = null
function getRepoStats() {
  if (repoStatsCache) return repoStatsCache
  const map = new Map()
  for (const commit of state.data.commits) {
    let entry = map.get(commit.project)
    if (!entry) {
      entry = { commits: 0, last: "" }
      map.set(commit.project, entry)
    }
    entry.commits += 1
    if (commit.date > entry.last) entry.last = commit.date
  }
  repoStatsCache = map
  return map
}

function renderRepoInfo() {
  dom.repoInfoList.textContent = ""
  const stats = getRepoStats()
  state.data.repos.forEach((repo) => {
    const item = document.createElement("label")
    const input = document.createElement("input")
    const content = document.createElement("span")
    const name = document.createElement("div")
    const meta = document.createElement("div")
    const branch = document.createElement("span")
    const path = document.createElement("span")
    const stat = document.createElement("span")
    item.className = "repo-info-item"
    input.type = "checkbox"
    input.value = repo.name
    input.checked = state.selectedProjects.has(repo.name)
    if (input.checked) item.classList.add("selected")
    content.className = "repo-info-content"
    name.className = "repo-info-name"
    meta.className = "repo-info-meta"
    name.textContent = repo.name
    branch.textContent = `分支：${repo.branch}`
    path.textContent = repo.path
    const s = stats.get(repo.name)
    stat.className = "repo-stat"
    stat.textContent = s ? `提交 ${s.commits} 次 · 最近 ${s.last || "无"}` : "无提交"
    meta.append(branch, path, stat)
    content.append(name, meta)
    item.append(input, content)
    dom.repoInfoList.append(item)
  })
}

// 同步仓库栏的勾选状态、选中高亮、计数与全选框，避免点击后视觉不更新
function syncRepoInfo() {
  const total = state.data.repos.length
  const items = dom.repoInfoList.querySelectorAll(".repo-info-item")
  items.forEach((item) => {
    const input = item.querySelector('input[type="checkbox"]')
    if (!input) return
    const checked = state.selectedProjects.has(input.value)
    input.checked = checked
    item.classList.toggle("selected", checked)
  })
  const selected = state.selectedProjects.size
  if (dom.repoSelectedCount) dom.repoSelectedCount.textContent = `已选 ${selected} / 共 ${total}`
  const master = dom.repoMaster
  if (master) {
    master.checked = selected > 0 && selected === total
    master.indeterminate = selected > 0 && selected < total
  }
}

function renderPeriodChoices() {
  dom.periodChoices.textContent = ""
  periodOptions.forEach((option) => {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = option.label
    button.dataset.period = option.value
    if (state.period === option.value) button.classList.add("active")
    dom.periodChoices.append(button)
  })
}

function bindChoices(container, selectedSet) {
  container.addEventListener("change", (event) => {
    const input = event.target
    if (!(input instanceof HTMLInputElement)) return
    if (input.checked) selectedSet.add(input.value)
    else selectedSet.delete(input.value)
    render()
  })
}

function getRangeBounds() {
  return {
    min: state.data.data_range?.start_date || state.data.default_filter.start_date,
    max: state.data.data_range?.end_date || state.data.default_filter.end_date,
  }
}

function getCommitsForAuthorChoices() {
  const startDate = dom.startDate.value
  const endDate = dom.endDate.value

  return state.data.commits.filter((commit) => {
    if (startDate && commit.date < startDate) return false
    if (endDate && commit.date > endDate) return false
    if (!state.selectedProjects.has(commit.project)) return false
    return true
  })
}

function syncAuthorChoices() {
  const availableAuthors = [...new Set(getCommitsForAuthorChoices().map((commit) => commit.author))].sort((a, b) => a.localeCompare(b, "zh-CN"))
  // 原地更新 state.selectedAuthors，保持 bindChoices 捕获的引用始终有效；
  // 若整体替换为新 Set，点击复选框会写入一个被 render 丢弃的旧对象，导致筛选失效。
  const filtered = new Set([...state.selectedAuthors].filter((author) => availableAuthors.includes(author)))
  state.selectedAuthors.clear()
  for (const author of filtered) state.selectedAuthors.add(author)
  renderChoices(dom.authorChoices, availableAuthors, state.selectedAuthors)
}

function resolvePeriodRange(period) {
  const { min, max } = getRangeBounds()
  const today = parseDate(max)

  if (period === "all") return { startDate: min, endDate: max }
  if (period === "last-7") return { startDate: clampDate(addDays(max, -6), min, max), endDate: max }
  if (period === "last-30") return { startDate: clampDate(addDays(max, -29), min, max), endDate: max }
  if (period === "last-90") return { startDate: clampDate(addDays(max, -89), min, max), endDate: max }
  if (period === "this-year") return { startDate: clampDate(`${today.getFullYear()}-01-01`, min, max), endDate: max }
  if (period === "this-month") {
    return { startDate: clampDate(`${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-01`, min, max), endDate: max }
  }
  if (period === "this-week") {
    const mondayOffset = today.getDay() === 0 ? -6 : 1 - today.getDay()
    return { startDate: clampDate(addDays(max, mondayOffset), min, max), endDate: max }
  }
  return {
    startDate: clampDate(dom.startDate.value || min, min, max),
    endDate: clampDate(dom.endDate.value || max, min, max),
  }
}

function applyPeriod(period) {
  const range = resolvePeriodRange(period)
  if (range.startDate > range.endDate) {
    const startDate = range.endDate
    range.endDate = range.startDate
    range.startDate = startDate
  }
  dom.startDate.value = range.startDate
  dom.endDate.value = range.endDate
  dom.customDateRange.classList.toggle("active", period === "custom")
  dom.dateRangeLabel.textContent = `当前周期：${range.startDate} 至 ${range.endDate}`
}

function getFilteredCommits() {
  const startDate = dom.startDate.value
  const endDate = dom.endDate.value

  return state.data.commits.filter((commit) => {
    if (startDate && commit.date < startDate) return false
    if (endDate && commit.date > endDate) return false
    if (!state.selectedProjects.has(commit.project)) return false
    if (state.selectedAuthors.size > 0 && !state.selectedAuthors.has(commit.author)) return false
    return true
  })
}

function groupCount(commits, key, seed = []) {
  const map = new Map(seed.map((item) => [item, 0]))
  commits.forEach((commit) => map.set(commit[key], (map.get(commit[key]) || 0) + 1))
  return [...map.entries()].map(([label, count]) => ({ label, count }))
}

function selectedText(selectedSet, allValues) {
  return selectedSet.size ? [...selectedSet].join("、") : allValues.join("、")
}

function showChartEmpty(canvasId, isEmpty) {
  const frame = document.getElementById(`${canvasId}Frame`)
  frame.classList.toggle("empty", isEmpty)
}

function destroyChart(canvasId) {
  const chart = chartMap.get(canvasId)
  if (chart) chart.destroy()
  chartMap.delete(canvasId)
}

function renderBarChart(canvasId, list, labelFormatter) {
  destroyChart(canvasId)
  const values = list.map((item) => item.count)
  const isEmpty = !list.length || Math.max(...values, 0) === 0
  showChartEmpty(canvasId, isEmpty)
  if (isEmpty) return

  const color = getCssVar("--color-primary")
  const chart = new Chart(document.getElementById(canvasId), {
    type: "bar",
    data: {
      labels: list.map((item) => labelFormatter(item.label)),
      datasets: [{ label: "提交次数", data: values, backgroundColor: color, borderColor: color, borderWidth: 1 }],
    },
    options: {
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: (context) => `提交次数：${formatNumber(context.raw)}` } },
      },
      scales: {
        y: { beginAtZero: true, ticks: { precision: 0 } },
      },
    },
  })
  chartMap.set(canvasId, chart)
}

function renderPieChart(canvasId, list) {
  destroyChart(canvasId)
  const rows = list.filter((item) => item.count > 0)
  showChartEmpty(canvasId, rows.length === 0)
  if (!rows.length) return

  const colors = chartColors()
  const total = rows.reduce((sum, item) => sum + item.count, 0)
  const chart = new Chart(document.getElementById(canvasId), {
    type: "pie",
    data: {
      labels: rows.map((item) => item.label),
      datasets: [{ data: rows.map((item) => item.count), backgroundColor: rows.map((_, index) => colors[index % colors.length]) }],
    },
    options: {
      maintainAspectRatio: false,
      plugins: {
        legend: { position: "bottom" },
        tooltip: {
          callbacks: {
            label: (context) => {
              const ratio = total ? ((context.raw / total) * 100).toFixed(1) : "0.0"
              return `${context.label}：${formatNumber(context.raw)} 次，${ratio}%`
            },
          },
        },
      },
    },
  })
  chartMap.set(canvasId, chart)
}

// ===== 增量展示：综合指标计算（与终端报告保持一致，筛选联动） =====
function escapeHtml(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function commitDateTime(commit) {
  return new Date(`${commit.date}T${String(commit.hour).padStart(2, "0")}:00:00`)
}

function computeStreaks(dates) {
  if (!dates.length) return { longest: 0, current: 0 }
  const sorted = [...new Set(dates)].sort()
  let longest = 1
  let current = 1
  for (let index = 1; index < sorted.length; index += 1) {
    const diff = Math.round((parseDate(sorted[index]) - parseDate(sorted[index - 1])) / 86400000)
    if (diff === 1) {
      current += 1
      if (current > longest) longest = current
    } else {
      current = 1
    }
  }
  let curStreak = 1
  for (let index = sorted.length - 1; index > 0; index -= 1) {
    const diff = Math.round((parseDate(sorted[index]) - parseDate(sorted[index - 1])) / 86400000)
    if (diff === 1) curStreak += 1
    else break
  }
  return { longest, current: curStreak }
}

function gini(values) {
  const vals = [...values].sort((a, b) => a - b)
  const n = vals.length
  if (!n || vals.reduce((sum, v) => sum + v, 0) === 0) return 0
  let cum = 0
  vals.forEach((v, i) => {
    cum += (i + 1) * v
  })
  const total = vals.reduce((sum, v) => sum + v, 0)
  return (2 * cum) / (n * total) - (n + 1) / n
}

function classifySubject(subject) {
  const text = (subject || "").toLowerCase()
  const bugKeywords = ["fix", "bug", "patch", "hotfix", "resolve", "修复", "解决"]
  const refactorKeywords = ["refactor", "cleanup", "clean", "optimize", "optimise", "restructure", "perf", "重构", "优化", "整理"]
  if (bugKeywords.some((k) => text.includes(k))) return "bug"
  if (refactorKeywords.some((k) => text.includes(k))) return "refactor"
  return "other"
}

const CONVENTIONAL_TYPES = ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"]
const MERGE_BRANCH_RE = /Merge branch '([^']+)'(?:\s+into\s+(\S+))?/
const MERGE_PR_RE = /Merge (?:pull request|PR) #?(\d+)(?:\s+from\s+(\S+))?/i
const REVERT_RE = /^Revert\s+"(.*)"/
const COMMIT_TYPE_LABELS = { feat: "新功能", fix: "修复", refactor: "重构", docs: "文档", test: "测试", style: "样式", perf: "性能", build: "构建", ci: "CI", chore: "杂务", revert: "回滚", merge: "合并", other: "其他" }
const COMMIT_TYPE_ORDER = ["feat", "fix", "refactor", "docs", "test", "style", "perf", "build", "ci", "chore", "revert", "merge", "other"]

function classifyCommitType(commit) {
  const subject = (commit.subject || "").trim()
  const lower = subject.toLowerCase()
  if (commit.is_merge || lower.startsWith("merge ")) return "merge"
  if (lower.startsWith("revert")) return "revert"
  const matched = lower.match(/^([a-z]+)(\([^)]*\))?!?:/)
  if (matched && CONVENTIONAL_TYPES.includes(matched[1])) return matched[1]
  const bugKeywords = ["fix", "bug", "patch", "hotfix", "resolve", "修复", "解决"]
  const refactorKeywords = ["refactor", "cleanup", "clean", "optimize", "optimise", "restructure", "perf", "重构", "优化", "整理"]
  if (bugKeywords.some((k) => lower.includes(k))) return "fix"
  if (refactorKeywords.some((k) => lower.includes(k))) return "refactor"
  if (["doc", "readme", "文档"].some((k) => lower.includes(k))) return "docs"
  if (["test", "测试"].some((k) => lower.includes(k))) return "test"
  return "other"
}

function sortedCountList(counter, keyName, limit) {
  // 与 Python sorted_count_list 同口径：次数降序、名称升序
  return Object.entries(counter)
    .sort((a, b) => (b[1] - a[1]) || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, limit)
    .map(([k, v]) => ({ [keyName]: k, count: v }))
}

function buildMetrics(commits) {
  const empty = {
    time_span: {},
    cadence: {},
    monthly_trend: [],
    code_changes: { top_files: [] },
    concentration: {},
    time_health: {},
    work_categories: {},
    commit_quality: {},
    merge_analysis: {},
    revert_analysis: {},
    commit_types: {},
    ownership: {},
    authors: [],
    projects: [],
  }
  if (!commits.length) return empty

  const dates = commits.map((c) => c.date)
  const first = dates.reduce((a, b) => (a < b ? a : b))
  const last = dates.reduce((a, b) => (a > b ? a : b))
  const spanDays = dateDiffDays(first, last)
  const activeSet = new Set(dates)
  const activeDays = activeSet.size
  const activeDayRatio = spanDays ? (activeDays / spanDays) * 100 : 0

  const byDay = {}
  commits.forEach((c) => {
    byDay[c.date] = (byDay[c.date] || 0) + 1
  })
  const dayCounts = Object.values(byDay)
  const maxDay = Math.max(...dayCounts)
  const peakDayDate = Object.keys(byDay).find((d) => byDay[d] === maxDay)
  const avgPerActiveDay = activeDays ? commits.length / activeDays : 0
  const commitSpike = avgPerActiveDay ? maxDay / avgPerActiveDay - 1 : 0
  const { longest, current } = computeStreaks(dates)

  const sortedByTime = [...commits].sort((a, b) => (a.time < b.time ? -1 : a.time > b.time ? 1 : 0))
  const intervals = []
  for (let i = 1; i < sortedByTime.length; i += 1) {
    const delta = (commitDateTime(sortedByTime[i]) - commitDateTime(sortedByTime[i - 1])) / 60000
    if (delta >= 0) intervals.push(delta)
  }
  const avgInterval = intervals.length ? intervals.reduce((a, b) => a + b, 0) / intervals.length : 0

  const weekCounts = groupCount(commits, "week_day", ["1", "2", "3", "4", "5", "6", "7"])
  const peakWeekday = weekCounts.reduce((m, it) => (it.count > m.count ? it : m)).label
  const hourCounts = groupCount(commits, "hour", Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0")))
  const peakHour = hourCounts.reduce((m, it) => (it.count > m.count ? it : m)).label

  const monthlyMap = {}
  commits.forEach((c) => {
    const m = c.date.slice(0, 7)
    if (!monthlyMap[m]) monthlyMap[m] = { month: m, commits: 0, added: 0, deleted: 0, authors: new Set(), active_days: new Set() }
    monthlyMap[m].commits += 1
    monthlyMap[m].added += c.added
    monthlyMap[m].deleted += c.deleted
    monthlyMap[m].authors.add(c.author)
    monthlyMap[m].active_days.add(c.date)
  })
  const monthly_trend = Object.values(monthlyMap)
    .sort((a, b) => (a.month < b.month ? -1 : 1))
    .map((e) => ({ month: e.month, commits: e.commits, added: e.added, deleted: e.deleted, authors: e.authors.size, active_days: e.active_days.size }))

  const totalAdded = commits.reduce((s, c) => s + c.added, 0)
  const totalDeleted = commits.reduce((s, c) => s + c.deleted, 0)
  const totalChanged = totalAdded + totalDeleted
  const avgLines = commits.length ? totalChanged / commits.length : 0
  const maxCommit = commits.reduce((m, c) => (c.added + c.deleted > m.added + m.deleted ? c : m))
  const maxTotal = maxCommit.added + maxCommit.deleted
  const totalFilesChanged = commits.reduce((s, c) => s + c.files.length, 0)
  const fileMap = {}
  commits.forEach((c) => {
    c.files.forEach((f) => {
      if (!fileMap[f.file]) fileMap[f.file] = { file: f.file, changes: 0, added: 0, deleted: 0 }
      fileMap[f.file].changes += 1
      fileMap[f.file].added += f.added
      fileMap[f.file].deleted += f.deleted
    })
  })
  const uniqueFiles = Object.keys(fileMap).length
  const top_files = Object.values(fileMap).sort((a, b) => b.changes - a.changes).slice(0, 10)
  const emptyCommits = commits.filter((c) => c.added === 0 && c.deleted === 0 && c.files.length === 0).length
  const largeCommits = commits.filter((c) => c.added + c.deleted > 500).length
  const churnRatio = totalChanged ? (totalDeleted / totalChanged) * 100 : 0

  const authorCounts = groupCount(commits, "author").sort((a, b) => b.count - a.count)
  const totalN = commits.length
  const top1 = authorCounts.length ? (authorCounts[0].count / (totalN || 1)) * 100 : 0
  const top2 = authorCounts.slice(0, 2).reduce((s, a) => s + a.count, 0) / (totalN || 1) * 100
  const giniVal = gini(authorCounts.map((a) => a.count))
  let bus = 0
  let cum = 0
  for (const a of authorCounts) {
    cum += a.count
    bus += 1
    if (cum >= totalN * 0.5) break
  }
  bus = bus || authorCounts.length
  let pareto = 0
  cum = 0
  for (const a of authorCounts) {
    cum += a.count
    pareto += 1
    if (cum >= totalN * 0.8) break
  }
  pareto = pareto || authorCounts.length

  const nightCommits = commits.filter((c) => ["22", "23", "00", "01", "02", "03", "04"].includes(c.hour)).length
  const weekendCommits = commits.filter((c) => c.week_day === "6" || c.week_day === "7").length
  const worktimeCommits = commits.filter((c) => ["09", "10", "11", "12", "13", "14", "15", "16", "17", "18"].includes(c.hour)).length
  const offhoursCommits = totalN - worktimeCommits

  const cat = { bug: 0, refactor: 0, other: 0 }
  commits.forEach((c) => {
    cat[classifySubject(c.subject)] += 1
  })
  const bugRatio = (cat.bug / (totalN || 1)) * 100
  const refactorRatio = (cat.refactor / (totalN || 1)) * 100
  const otherRatio = (cat.other / (totalN || 1)) * 100

  const mergeCommits = commits.filter((c) => c.is_merge || (c.subject || "").toLowerCase().startsWith("merge")).length
  const botCommits = commits.filter((c) => /bot|\[bot\]|ci|jenkins|github-actions|automation|runner/i.test(c.author + c.email)).length
  const avgSubjectLen = commits.reduce((s, c) => s + Array.from(c.subject || "").length, 0) / (totalN || 1)
  const avgSubjectWords = commits.reduce((s, c) => s + (c.subject || "").split(/\s+/).filter(Boolean).length, 0) / (totalN || 1)

  const authorMetrics = authorCounts.map(({ label: author, count }) => {
    const ac = commits.filter((c) => c.author === author)
    const adates = ac.map((c) => c.date)
    const aAdded = ac.reduce((s, c) => s + c.added, 0)
    const aDeleted = ac.reduce((s, c) => s + c.deleted, 0)
    const aActive = new Set(adates).size
    const aFirst = adates.reduce((a, b) => (a < b ? a : b))
    const aLast = adates.reduce((a, b) => (a > b ? a : b))
    const { longest: aL, current: aC } = computeStreaks(adates)
    const aPeakHour = groupCount(ac, "hour", Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0")))
      .reduce((m, it) => (it.count > m.count ? it : m)).label
    const aPeakWd = groupCount(ac, "week_day", ["1", "2", "3", "4", "5", "6", "7"])
      .reduce((m, it) => (it.count > m.count ? it : m)).label
    const aFiles = new Set(ac.flatMap((c) => c.files.map((f) => f.file))).size
    return {
      author,
      commits: count,
      commit_ratio: (count / (totalN || 1)) * 100,
      added: aAdded,
      deleted: aDeleted,
      active_days: aActive,
      first_commit: aFirst,
      last_commit: aLast,
      longest_streak: aL,
      current_streak: aC,
      peak_hour: `${aPeakHour}:00`,
      peak_weekday: weekLabels[aPeakWd] || aPeakWd,
      avg_per_active_day: aActive ? count / aActive : 0,
      unique_files: aFiles,
    }
  })

  const projectMetrics = [...new Set(commits.map((c) => c.project))]
    .sort()
    .map((project) => {
      const pc = commits.filter((c) => c.project === project)
      return {
        project,
        commits: pc.length,
        added: pc.reduce((s, c) => s + c.added, 0),
        deleted: pc.reduce((s, c) => s + c.deleted, 0),
        authors: new Set(pc.map((c) => c.author)).size,
        active_days: new Set(pc.map((c) => c.date)).size,
      }
    })

  // ===== 合并分析（与 Python build_metrics 同口径）=====
  const merges = commits.filter((c) => c.is_merge)
  const mergeAuthorCounts = {}
  const mergeSourceCounts = {}
  let prMergeCount = 0
  merges.forEach((c) => {
    mergeAuthorCounts[c.author] = (mergeAuthorCounts[c.author] || 0) + 1
    const subject = c.subject || ""
    const prMatch = subject.match(MERGE_PR_RE)
    if (prMatch) {
      prMergeCount += 1
      if (prMatch[2]) mergeSourceCounts[prMatch[2]] = (mergeSourceCounts[prMatch[2]] || 0) + 1
      return
    }
    const brMatch = subject.match(MERGE_BRANCH_RE)
    if (brMatch) mergeSourceCounts[brMatch[1]] = (mergeSourceCounts[brMatch[1]] || 0) + 1
  })
  const conflictMerges = merges.filter((c) => (c.conflict_files || []).length)
  const conflictResolverCounts = {}
  const conflictFileCounts = {}
  conflictMerges.forEach((c) => {
    conflictResolverCounts[c.author] = (conflictResolverCounts[c.author] || 0) + 1
    ;(c.conflict_files || []).forEach((name) => {
      conflictFileCounts[name] = (conflictFileCounts[name] || 0) + 1
    })
  })
  const mergeAnalysis = {
    total_merges: merges.length,
    merge_ratio: (merges.length / (totalN || 1)) * 100,
    pr_merges: prMergeCount,
    branch_merges: merges.length - prMergeCount,
    merge_by_author: sortedCountList(mergeAuthorCounts, "author", 10),
    merge_sources: sortedCountList(mergeSourceCounts, "branch", 10),
    conflict_merges: conflictMerges.length,
    conflict_ratio: merges.length ? (conflictMerges.length / merges.length) * 100 : 0,
    conflict_resolvers: sortedCountList(conflictResolverCounts, "author", 10),
    conflict_files: sortedCountList(conflictFileCounts, "file", 10),
  }

  // ===== 问题溯源：Revert 与 Bug 高发文件 =====
  const subjectAuthorIndex = {}
  commits.forEach((c) => {
    const subj = (c.subject || "").trim()
    if (!REVERT_RE.test(subj) && !(subj in subjectAuthorIndex)) subjectAuthorIndex[subj] = c.author
  })
  const reverts = []
  const revertAuthorCounts = {}
  commits.forEach((c) => {
    const matched = ((c.subject || "").trim()).match(REVERT_RE)
    if (matched) {
      reverts.push([c, matched[1]])
      revertAuthorCounts[c.author] = (revertAuthorCounts[c.author] || 0) + 1
    }
  })
  const revertedAuthorCounts = {}
  reverts.forEach(([, origSubject]) => {
    const origAuthor = subjectAuthorIndex[origSubject.trim()]
    if (origAuthor) revertedAuthorCounts[origAuthor] = (revertedAuthorCounts[origAuthor] || 0) + 1
  })
  const bugProneCounts = {}
  commits.forEach((c) => {
    if (classifySubject(c.subject) === "bug") {
      c.files.forEach((f) => {
        bugProneCounts[f.file] = (bugProneCounts[f.file] || 0) + 1
      })
    }
  })
  const revertAnalysis = {
    revert_commits: reverts.length,
    revert_ratio: (reverts.length / (totalN || 1)) * 100,
    revert_by_author: sortedCountList(revertAuthorCounts, "author", 10),
    reverted_authors: sortedCountList(revertedAuthorCounts, "author", 10),
    bug_prone_files: sortedCountList(bugProneCounts, "file", 10),
  }

  // ===== 提交类型细分（Conventional Commits）=====
  const typeCounts = {}
  const authorTypeCounts = {}
  commits.forEach((c) => {
    const cType = classifyCommitType(c)
    typeCounts[cType] = (typeCounts[cType] || 0) + 1
    if (!authorTypeCounts[c.author]) authorTypeCounts[c.author] = {}
    authorTypeCounts[c.author][cType] = (authorTypeCounts[c.author][cType] || 0) + 1
  })
  const typeDistribution = COMMIT_TYPE_ORDER.filter((t) => typeCounts[t]).map((t) => ({
    type: t,
    count: typeCounts[t],
    ratio: (typeCounts[t] / (totalN || 1)) * 100,
  }))
  const typesByAuthor = authorCounts.map(({ label: author }) => {
    const row = { author }
    COMMIT_TYPE_ORDER.forEach((t) => {
      row[t] = (authorTypeCounts[author] || {})[t] || 0
    })
    return row
  })
  const commitTypes = { distribution: typeDistribution, by_author: typesByAuthor }

  // ===== 文件所有权与协作 =====
  const fileAuthorCommits = {}
  commits.forEach((c) => {
    c.files.forEach((f) => {
      if (!fileAuthorCommits[f.file]) fileAuthorCommits[f.file] = {}
      fileAuthorCommits[f.file][c.author] = (fileAuthorCommits[f.file][c.author] || 0) + 1
    })
  })
  const totalTrackedFiles = Object.keys(fileAuthorCommits).length
  const singleOwnerFiles = Object.values(fileAuthorCommits).filter((amap) => Object.keys(amap).length === 1).length
  const fileOwners = top_files
    .filter((entry) => fileAuthorCommits[entry.file])
    .map((entry) => {
      const amap = fileAuthorCommits[entry.file]
      const [owner, ownerN] = Object.entries(amap).sort((a, b) => (b[1] - a[1]) || (a[0] < b[0] ? -1 : 1))[0]
      const fileTotal = Object.values(amap).reduce((s, n) => s + n, 0)
      return {
        file: entry.file,
        owner,
        owner_commits: ownerN,
        total_commits: fileTotal,
        owner_ratio: fileTotal ? (ownerN / fileTotal) * 100 : 0,
        author_count: Object.keys(amap).length,
      }
    })
  const pairCounts = {}
  Object.values(fileAuthorCommits).forEach((amap) => {
    const authorsSorted = Object.keys(amap).sort()
    if (authorsSorted.length < 2) return
    for (let i = 0; i < authorsSorted.length; i += 1) {
      for (let j = i + 1; j < authorsSorted.length; j += 1) {
        const key = `${authorsSorted[i]} ↔ ${authorsSorted[j]}`
        pairCounts[key] = (pairCounts[key] || 0) + 1
      }
    }
  })
  const ownership = {
    total_files: totalTrackedFiles,
    single_owner_files: singleOwnerFiles,
    single_owner_ratio: totalTrackedFiles ? (singleOwnerFiles / totalTrackedFiles) * 100 : 0,
    shared_files: totalTrackedFiles - singleOwnerFiles,
    file_owners: fileOwners,
    collaboration_pairs: sortedCountList(pairCounts, "pair", 5),
  }

  return {
    time_span: {
      first_commit_date: first,
      last_commit_date: last,
      span_days: spanDays,
      active_days: activeDays,
      active_day_ratio: activeDayRatio,
    },
    cadence: {
      avg_commits_per_active_day: avgPerActiveDay,
      max_commits_in_one_day: maxDay,
      peak_day_date: peakDayDate,
      commit_spike: commitSpike,
      longest_streak: longest,
      current_streak: current,
      avg_interval_minutes: avgInterval,
      peak_weekday: weekLabels[peakWeekday] || peakWeekday,
      peak_hour: `${peakHour}:00`,
    },
    monthly_trend,
    code_changes: {
      avg_lines_per_commit: avgLines,
      max_commit_added: maxCommit.added,
      max_commit_deleted: maxCommit.deleted,
      max_commit_total: maxTotal,
      max_commit_author: maxCommit.author,
      max_commit_date: maxCommit.date,
      max_commit_subject: maxCommit.subject,
      total_files_changed: totalFilesChanged,
      unique_files: uniqueFiles,
      empty_commits: emptyCommits,
      large_commits: largeCommits,
      churn_ratio: churnRatio,
      top_files,
    },
    concentration: {
      top1_ratio: top1,
      top2_ratio: top2,
      gini: giniVal,
      bus_factor: bus,
      pareto_80: pareto,
    },
    time_health: {
      night_commits: nightCommits,
      night_ratio: (nightCommits / (totalN || 1)) * 100,
      weekend_commits: weekendCommits,
      weekend_ratio: (weekendCommits / (totalN || 1)) * 100,
      worktime_commits: worktimeCommits,
      worktime_ratio: (worktimeCommits / (totalN || 1)) * 100,
      offhours_commits: offhoursCommits,
      offhours_ratio: (offhoursCommits / (totalN || 1)) * 100,
    },
    work_categories: {
      bug_fix_commits: cat.bug,
      bug_fix_ratio: bugRatio,
      refactor_commits: cat.refactor,
      refactor_ratio: refactorRatio,
      other_commits: cat.other,
      other_ratio: otherRatio,
    },
    commit_quality: {
      merge_commits: mergeCommits,
      merge_ratio: (mergeCommits / (totalN || 1)) * 100,
      bot_commits: botCommits,
      avg_subject_length: avgSubjectLen,
      avg_subject_words: avgSubjectWords,
    },
    merge_analysis: mergeAnalysis,
    revert_analysis: revertAnalysis,
    commit_types: commitTypes,
    ownership,
    authors: authorMetrics,
    projects: projectMetrics,
  }
}

function buildSummary(commits) {
  const added = commits.reduce((sum, commit) => sum + commit.added, 0)
  const deleted = commits.reduce((sum, commit) => sum + commit.deleted, 0)
  const startDate = dom.startDate.value || state.data.default_filter.start_date
  const endDate = dom.endDate.value || state.data.default_filter.end_date
  const days = dateDiffDays(startDate, endDate)
  const work = estimateHours(commits)
  const dailyHours = work.workDays ? work.totalHours / work.workDays : 0
  const weeklyHours = dailyHours * 5
  const overtimeHours = Math.max(weeklyHours - 40, 0)
  const overtimeRatio = weeklyHours ? (overtimeHours / weeklyHours) * 100 : 0

  return {
    repoCount: state.selectedProjects.size,
    activeProjectCount: uniqueCount(commits, (item) => item.project),
    added,
    deleted,
    net: added - deleted,
    days,
    dailyCommits: commits.length / days,
    dailyHours,
    weeklyHours,
    overtimeRatio,
  }
}

function renderSummary(commits) {
  const summary = buildSummary(commits)

  document.getElementById("repoCount").textContent = formatNumber(summary.repoCount)
  document.getElementById("activeProjectCount").textContent = formatNumber(summary.activeProjectCount)
  document.getElementById("commitCount").textContent = formatNumber(commits.length)
  document.getElementById("addedLines").textContent = formatNumber(summary.added)
  document.getElementById("deletedLines").textContent = formatNumber(summary.deleted)
  document.getElementById("netLines").textContent = formatNumber(summary.net)
  document.getElementById("dailyCommits").textContent = summary.dailyCommits.toFixed(1)
  document.getElementById("dailyWorkHours").textContent = `${summary.dailyHours.toFixed(1)}h`
  document.getElementById("weeklyWorkHours").textContent = `${summary.weeklyHours.toFixed(1)}h`
  document.getElementById("overtimeRatio").textContent = `${summary.overtimeRatio.toFixed(1)}%`
}

function buildAuthorRows(commits) {
  const map = new Map()
  commits.forEach((commit) => {
    if (!map.has(commit.author)) {
      map.set(commit.author, { author: commit.author, commits: 0, added: 0, deleted: 0, dates: new Set() })
    }
    const row = map.get(commit.author)
    row.commits += 1
    row.added += commit.added
    row.deleted += commit.deleted
    row.dates.add(commit.date)
  })
  return [...map.values()].sort((a, b) => b.commits - a.commits)
}

function renderAuthorTable(commits) {
  const rows = buildAuthorRows(commits)
  document.getElementById("authorTable").innerHTML = rows.length
    ? rows
        .map(
          (row) => `
            <tr>
              <td>${row.author}</td>
              <td>${formatNumber(row.commits)}</td>
              <td>${formatNumber(row.added)}</td>
              <td>${formatNumber(row.deleted)}</td>
              <td>${formatNumber(row.dates.size)}</td>
            </tr>
          `
        )
        .join("")
    : '<tr><td colspan="5">当前筛选条件下没有数据</td></tr>'
}

function getCurrentFilterRange() {
  return {
    startDate: dom.startDate.value || state.data.default_filter.start_date,
    endDate: dom.endDate.value || state.data.default_filter.end_date,
  }
}

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;")
}

function createInlineStringCell(ref, value, styleIndex = 0) {
  return `<c r="${ref}" s="${styleIndex}" t="inlineStr"><is><t>${escapeXml(value)}</t></is></c>`
}

function createNumberCell(ref, value, styleIndex = 0) {
  return `<c r="${ref}" s="${styleIndex}"><v>${value}</v></c>`
}

function createEmptyCell(ref, styleIndex = 0) {
  return `<c r="${ref}" s="${styleIndex}"/>`
}

function createPercentCell(ref, value, styleIndex = 0) {
  return `<c r="${ref}" s="${styleIndex}"><v>${value}</v></c>`
}

function buildProjectExportRows(commits) {
  const rows = new Map()
  commits.forEach((commit) => {
    if (!rows.has(commit.project)) {
      rows.set(commit.project, {
        project: commit.project,
        totalLines: 0,
        added: 0,
        deleted: 0,
        commits: 0,
        authors: new Set(),
      })
    }
    const row = rows.get(commit.project)
    row.totalLines += commit.added + commit.deleted
    row.added += commit.added
    row.deleted += commit.deleted
    row.commits += 1
    row.authors.add(commit.author)
  })

  return [...rows.values()]
    .sort((a, b) => b.totalLines - a.totalLines)
    .map((row) => ({
      project: row.project,
      totalLines: row.totalLines,
      added: row.added,
      deleted: row.deleted,
      commitCount: row.commits,
      authorCount: row.authors.size,
      perAuthorLines: row.authors.size ? (row.totalLines / row.authors.size).toFixed(2) : "0.00",
    }))
}

function buildAuthorExportRows(commits) {
  const rowMap = new Map()
  const { startDate, endDate } = getCurrentFilterRange()
  const pullRequests = state.data.pull_requests || []

  commits.forEach((commit) => {
    const key = `${commit.project}@@${commit.author}`
    if (!rowMap.has(key)) {
      rowMap.set(key, {
        project: commit.project,
        author: commit.author,
        totalLines: 0,
        added: 0,
        deleted: 0,
        commitCount: 0,
      })
    }
    const row = rowMap.get(key)
    row.totalLines += commit.added + commit.deleted
    row.added += commit.added
    row.deleted += commit.deleted
    row.commitCount += 1
  })

  return [...rowMap.values()]
    .map((row) => {
      const submittedPrs = pullRequests.filter(
        (pr) => pr.project === row.project && pr.author === row.author && pr.created_at.slice(0, 10) >= startDate && pr.created_at.slice(0, 10) <= endDate
      )
      const mergedPrCount = submittedPrs.filter((pr) => pr.merged_at).length
      const submittedMrCount = submittedPrs.length
      return {
        ...row,
        reviewPassRate: submittedMrCount ? mergedPrCount / submittedMrCount : null,
      }
    })
    .sort((a, b) => b.totalLines - a.totalLines || a.author.localeCompare(b.author, "zh-CN"))
}

function buildProjectSheetXml(commits) {
  const { startDate, endDate } = getCurrentFilterRange()
  const projectRows = buildProjectExportRows(commits)
  const totalRows = Math.max(projectRows.length, 2)
  const sheetRows = []

  sheetRows.push(
    `<row r="1">${[
      createInlineStringCell("A1", "时间：", 6),
      createInlineStringCell("B1", "开始时间", 7),
      createInlineStringCell("C1", startDate, 8),
      createInlineStringCell("D1", "结束时间", 7),
      createInlineStringCell("E1", endDate, 8),
      createEmptyCell("F1", 8),
      createEmptyCell("G1", 8),
    ].join("")}</row>`
  )
  sheetRows.push(
    `<row r="2">${[
      createInlineStringCell("A2", "项目代码情况", 2),
      createEmptyCell("B2", 2),
      createEmptyCell("C2", 2),
      createEmptyCell("D2", 2),
      createInlineStringCell("E2", "人均生产力", 2),
      createEmptyCell("F2", 2),
      createEmptyCell("G2", 2),
    ].join("")}</row>`
  )
  sheetRows.push(
    `<row r="3">${[
      createInlineStringCell("A3", "项目名", 3),
      createInlineStringCell("B3", "提交代码总行数", 3),
      createInlineStringCell("C3", "新增代码行数", 3),
      createInlineStringCell("D3", "删除代码行数", 3),
      createInlineStringCell("E3", "本周期提交次数", 3),
      createInlineStringCell("F3", "本周期提交人次", 3),
      createInlineStringCell("G3", "本周期人均提交代码行数", 3),
    ].join("")}</row>`
  )

  for (let index = 0; index < totalRows; index += 1) {
    const rowNumber = index + 4
    const row = projectRows[index]
    sheetRows.push(
      `<row r="${rowNumber}">${[
        createInlineStringCell(`A${rowNumber}`, row ? row.project : "", 2),
        row ? createNumberCell(`B${rowNumber}`, row.totalLines, 2) : createEmptyCell(`B${rowNumber}`, 2),
        row ? createNumberCell(`C${rowNumber}`, row.added, 2) : createEmptyCell(`C${rowNumber}`, 2),
        row ? createNumberCell(`D${rowNumber}`, row.deleted, 2) : createEmptyCell(`D${rowNumber}`, 2),
        row ? createNumberCell(`E${rowNumber}`, row.totalLines, 2) : createEmptyCell(`E${rowNumber}`, 2),
        row ? createNumberCell(`F${rowNumber}`, row.commitCount, 2) : createEmptyCell(`F${rowNumber}`, 2),
        row ? createNumberCell(`G${rowNumber}`, row.perAuthorLines, 2) : createEmptyCell(`G${rowNumber}`, 2),
      ].join("")}</row>`
    )
  }

  const lastRow = totalRows + 3
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1:G${lastRow}"/>
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
    ${sheetRows.join("")}
  </sheetData>
  <mergeCells count="2">
    <mergeCell ref="A2:D2"/>
    <mergeCell ref="E2:G2"/>
  </mergeCells>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>`
}

function buildAuthorSheetXml(commits) {
  const { startDate, endDate } = getCurrentFilterRange()
  const authorRows = buildAuthorExportRows(commits)
  const totalRows = Math.max(authorRows.length, 1)
  const sheetRows = []

  sheetRows.push(
    `<row r="1">${[
      createInlineStringCell("A1", "时间：", 6),
      createInlineStringCell("B1", "开始时间", 7),
      createInlineStringCell("C1", startDate, 8),
      createInlineStringCell("D1", "结束时间", 7),
      createInlineStringCell("E1", endDate, 8),
      createEmptyCell("F1", 8),
      createEmptyCell("G1", 8),
    ].join("")}</row>`
  )
  sheetRows.push(
    `<row r="2">${[
      createInlineStringCell("A2", "项目名称", 3),
      createInlineStringCell("B2", "姓名", 4),
      createInlineStringCell("C2", "提交总代码行", 4),
      createInlineStringCell("D2", "新增行数", 4),
      createInlineStringCell("E2", "删除行数", 4),
      createInlineStringCell("F2", "提交次数", 4),
      createInlineStringCell("G2", "代码审核合格率", 5),
    ].join("")}</row>`
  )

  for (let index = 0; index < totalRows; index += 1) {
    const rowNumber = index + 3
    const row = authorRows[index]
    sheetRows.push(
      `<row r="${rowNumber}">${[
        createInlineStringCell(`A${rowNumber}`, row ? row.project : "", 2),
        createInlineStringCell(`B${rowNumber}`, row ? row.author : "", 2),
        row ? createNumberCell(`C${rowNumber}`, row.totalLines, 2) : createEmptyCell(`C${rowNumber}`, 2),
        row ? createNumberCell(`D${rowNumber}`, row.added, 2) : createEmptyCell(`D${rowNumber}`, 2),
        row ? createNumberCell(`E${rowNumber}`, row.deleted, 2) : createEmptyCell(`E${rowNumber}`, 2),
        row ? createNumberCell(`F${rowNumber}`, row.commitCount, 2) : createEmptyCell(`F${rowNumber}`, 2),
        row
          ? row.reviewPassRate === null
            ? createInlineStringCell(`G${rowNumber}`, "--", 2)
            : createPercentCell(`G${rowNumber}`, row.reviewPassRate, 9)
          : createEmptyCell(`G${rowNumber}`, 2),
      ].join("")}</row>`
    )
  }

  const lastRow = totalRows + 2
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1:G${lastRow}"/>
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
    ${sheetRows.join("")}
  </sheetData>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>`
}

function buildXlsxStylesXml() {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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
</styleSheet>`
}

function buildXlsxFiles(commits) {
  const now = new Date().toISOString()
  return [
    {
      name: "[Content_Types].xml",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>`,
    },
    {
      name: "_rels/.rels",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>`,
    },
    {
      name: "docProps/app.xml",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>git-workload-report</Application>
  <HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>工作表</vt:lpstr></vt:variant><vt:variant><vt:i4>2</vt:i4></vt:variant></vt:vector></HeadingPairs>
  <TitlesOfParts><vt:vector size="2" baseType="lpstr"><vt:lpstr>Sheet1</vt:lpstr><vt:lpstr>Sheet2</vt:lpstr></vt:vector></TitlesOfParts>
</Properties>`,
    },
    {
      name: "docProps/core.xml",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:creator>git-workload-report</dc:creator>
  <cp:lastModifiedBy>git-workload-report</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">${now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">${now}</dcterms:modified>
</cp:coreProperties>`,
    },
    {
      name: "xl/workbook.xml",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
    <sheet name="Sheet2" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>`,
    },
    {
      name: "xl/_rels/workbook.xml.rels",
      content: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`,
    },
    { name: "xl/styles.xml", content: buildXlsxStylesXml() },
    { name: "xl/worksheets/sheet1.xml", content: buildProjectSheetXml(commits) },
    { name: "xl/worksheets/sheet2.xml", content: buildAuthorSheetXml(commits) },
  ]
}

function makeCrcTable() {
  const table = new Uint32Array(256)
  for (let index = 0; index < 256; index += 1) {
    let value = index
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1
    }
    table[index] = value >>> 0
  }
  return table
}

const crcTable = makeCrcTable()

function crc32(bytes) {
  let value = 0xffffffff
  for (const item of bytes) {
    value = crcTable[(value ^ item) & 0xff] ^ (value >>> 8)
  }
  return (value ^ 0xffffffff) >>> 0
}

function writeUint16(view, offset, value) {
  view.setUint16(offset, value, true)
}

function writeUint32(view, offset, value) {
  view.setUint32(offset, value, true)
}

function createStoredZip(files) {
  const preparedFiles = files.map((file) => {
    const nameBytes = textEncoder.encode(file.name)
    const contentBytes = textEncoder.encode(file.content)
    return {
      name: file.name,
      nameBytes,
      contentBytes,
      crc: crc32(contentBytes),
    }
  })

  const localParts = []
  const centralParts = []
  let offset = 0

  preparedFiles.forEach((file) => {
    const localHeader = new Uint8Array(30 + file.nameBytes.length)
    const localView = new DataView(localHeader.buffer)
    writeUint32(localView, 0, 0x04034b50)
    writeUint16(localView, 4, 20)
    writeUint16(localView, 6, 0)
    writeUint16(localView, 8, 0)
    writeUint16(localView, 10, 0)
    writeUint16(localView, 12, 0)
    writeUint32(localView, 14, file.crc)
    writeUint32(localView, 18, file.contentBytes.length)
    writeUint32(localView, 22, file.contentBytes.length)
    writeUint16(localView, 26, file.nameBytes.length)
    writeUint16(localView, 28, 0)
    localHeader.set(file.nameBytes, 30)
    localParts.push(localHeader, file.contentBytes)

    const centralHeader = new Uint8Array(46 + file.nameBytes.length)
    const centralView = new DataView(centralHeader.buffer)
    writeUint32(centralView, 0, 0x02014b50)
    writeUint16(centralView, 4, 20)
    writeUint16(centralView, 6, 20)
    writeUint16(centralView, 8, 0)
    writeUint16(centralView, 10, 0)
    writeUint16(centralView, 12, 0)
    writeUint16(centralView, 14, 0)
    writeUint32(centralView, 16, file.crc)
    writeUint32(centralView, 20, file.contentBytes.length)
    writeUint32(centralView, 24, file.contentBytes.length)
    writeUint16(centralView, 28, file.nameBytes.length)
    writeUint16(centralView, 30, 0)
    writeUint16(centralView, 32, 0)
    writeUint16(centralView, 34, 0)
    writeUint16(centralView, 36, 0)
    writeUint32(centralView, 38, 0)
    writeUint32(centralView, 42, offset)
    centralHeader.set(file.nameBytes, 46)
    centralParts.push(centralHeader)

    offset += localHeader.length + file.contentBytes.length
  })

  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0)
  const endRecord = new Uint8Array(22)
  const endView = new DataView(endRecord.buffer)
  writeUint32(endView, 0, 0x06054b50)
  writeUint16(endView, 4, 0)
  writeUint16(endView, 6, 0)
  writeUint16(endView, 8, preparedFiles.length)
  writeUint16(endView, 10, preparedFiles.length)
  writeUint32(endView, 12, centralSize)
  writeUint32(endView, 16, offset)
  writeUint16(endView, 20, 0)

  return new Blob([...localParts, ...centralParts, endRecord], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  })
}

function downloadBlob(blob, fileName) {
  const link = document.createElement("a")
  const downloadUrl = URL.createObjectURL(blob)
  link.href = downloadUrl
  link.download = fileName
  document.body.append(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(downloadUrl)
}

function buildTimestampFileName(prefix, extension) {
  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, "0")
  const day = String(now.getDate()).padStart(2, "0")
  const hours = String(now.getHours()).padStart(2, "0")
  const minutes = String(now.getMinutes()).padStart(2, "0")
  return `${prefix}_${year}${month}${day}${hours}${minutes}.${extension}`
}

function escapeCsvValue(value) {
  const text = value == null ? "" : String(value)
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`
  }
  return text
}

function buildExportCsv(commits) {
  const { startDate, endDate } = getCurrentFilterRange()
  const projectRows = buildProjectExportRows(commits)
  const authorRows = buildAuthorExportRows(commits)
  const lines = []

  const pushRow = (values) => {
    lines.push(values.map(escapeCsvValue).join(","))
  }

  pushRow(["统计维度", "开始时间", startDate, "结束时间", endDate])
  pushRow([])
  pushRow(["项目维度"])
  pushRow(["项目名称", "代码总行数", "新增行数", "删除行数", "提交代码总行数", "提交次数", "人均代码行数"])
  projectRows.forEach((row) => {
    pushRow([row.project, row.totalLines, row.added, row.deleted, row.totalLines, row.commitCount, row.perAuthorLines])
  })
  pushRow([])
  pushRow(["人员维度"])
  pushRow(["项目名称", "姓名", "提交总代码行", "新增行数", "删除行数", "提交次数", "代码审核合格率"])
  authorRows.forEach((row) => {
    pushRow([
      row.project,
      row.author,
      row.totalLines,
      row.added,
      row.deleted,
      row.commitCount,
      row.reviewPassRate === null ? "--" : `${(row.reviewPassRate * 100).toFixed(2)}%`,
    ])
  })

  return `\uFEFF${lines.join("\r\n")}`
}

/**
 * 导出的 txt 必须只使用当前页面筛选后的 commits。
 * 用户在页面上勾选仓库、开发者和时间段后，看到的结果必须和导出的结果保持一致。
 */
function metricsToTextLines(metrics) {
  const ts = metrics.time_span || {}
  const cd = metrics.cadence || {}
  const cc = metrics.code_changes || {}
  const cn = metrics.concentration || {}
  const th = metrics.time_health || {}
  const wc = metrics.work_categories || {}
  const cq = metrics.commit_quality || {}
  const lines = []
  const push = (s) => lines.push(s)

  if (Object.keys(ts).length) {
    push("时间跨度与活跃度")
    push(`首次提交：${ts.first_commit_date || "-"}`)
    push(`最近提交：${ts.last_commit_date || "-"}`)
    push(`时间跨度：${ts.span_days || 0} 天`)
    push(`活跃天数：${ts.active_days || 0} 天`)
    push(`活跃密度：${(ts.active_day_ratio || 0).toFixed(1)}%`)
    push("")
  }
  if (Object.keys(cd).length) {
    push("提交节奏")
    push(`最忙一天：${cd.peak_day_date || "-"}（${cd.max_commits_in_one_day || 0} 次）`)
    push(`提交尖峰：${(cd.commit_spike || 0).toFixed(1)}x`)
    push(`最长连续提交：${cd.longest_streak || 0} 天`)
    push(`当前连续提交：${cd.current_streak || 0} 天`)
    push(`平均提交间隔：${Math.round(cd.avg_interval_minutes || 0)} 分钟`)
    push(`最活跃星期：${cd.peak_weekday || "-"}`)
    push(`最活跃时段：${cd.peak_hour || "-"}`)
    push("")
  }
  if (metrics.monthly_trend && metrics.monthly_trend.length) {
    push("月度提交趋势")
    metrics.monthly_trend.forEach((m) =>
      push(`${m.month}：提交 ${formatNumber(m.commits)}，新增 ${formatNumber(m.added)}，删除 ${formatNumber(m.deleted)}，开发者 ${m.authors}，活跃天 ${m.active_days}`)
    )
    push("")
  }
  if (Object.keys(cc).length) {
    push("代码改动概览")
    push(`平均每次提交改动：${(cc.avg_lines_per_commit || 0).toFixed(1)} 行`)
    push(`最大单次提交：+${formatNumber(cc.max_commit_added || 0)} / -${formatNumber(cc.max_commit_deleted || 0)}（${cc.max_commit_author || "-"}，${cc.max_commit_date || "-"}）`)
    if (cc.max_commit_subject) push(`提交说明：${cc.max_commit_subject}`)
    push(`改动文件次数：${formatNumber(cc.total_files_changed || 0)}（去重 ${formatNumber(cc.unique_files || 0)} 个文件）`)
    push(`大型提交（>500 行）：${cc.large_commits || 0} 次`)
    push(`空提交（无代码改动）：${cc.empty_commits || 0} 次`)
    push(`代码周转比：${(cc.churn_ratio || 0).toFixed(1)}%`)
    push("")
  }
  if (cc.top_files && cc.top_files.length) {
    push("热点文件 Top 10")
    cc.top_files.forEach((f) =>
      push(`${f.file}：改动 ${formatNumber(f.changes)} 次，新增 ${formatNumber(f.added)}，删除 ${formatNumber(f.deleted)}`)
    )
    push("")
  }
  if (Object.keys(cn).length) {
    push("开发者贡献集中度")
    push(`Top 1 占比：${(cn.top1_ratio || 0).toFixed(1)}%`)
    push(`Top 2 占比：${(cn.top2_ratio || 0).toFixed(1)}%`)
    push(`基尼系数：${(cn.gini || 0).toFixed(2)}`)
    push(`Bus Factor：${cn.bus_factor || 0} 人`)
    push(`帕累托 80%：${cn.pareto_80 || 0} 人`)
    push("")
  }
  if (Object.keys(th).length) {
    push("时间健康度")
    push(`深夜提交（22:00-05:00）：${formatNumber(th.night_commits || 0)} 次（${(th.night_ratio || 0).toFixed(1)}%）`)
    push(`周末提交（周六/日）：${formatNumber(th.weekend_commits || 0)} 次（${(th.weekend_ratio || 0).toFixed(1)}%）`)
    push(`工作时间（09:00-18:00）：${formatNumber(th.worktime_commits || 0)} 次（${(th.worktime_ratio || 0).toFixed(1)}%）`)
    push(`非工作时间：${formatNumber(th.offhours_commits || 0)} 次（${(th.offhours_ratio || 0).toFixed(1)}%）`)
    push("")
  }
  if (Object.keys(wc).length) {
    push("工作类型分布")
    push(`Bug 修复：${formatNumber(wc.bug_fix_commits || 0)} 次（${(wc.bug_fix_ratio || 0).toFixed(1)}%）`)
    push(`重构优化：${formatNumber(wc.refactor_commits || 0)} 次（${(wc.refactor_ratio || 0).toFixed(1)}%）`)
    push(`其他：${formatNumber(wc.other_commits || 0)} 次（${(wc.other_ratio || 0).toFixed(1)}%）`)
    push("")
  }
  if (Object.keys(cq).length) {
    push("提交质量")
    push(`合并提交：${formatNumber(cq.merge_commits || 0)} 次（${(cq.merge_ratio || 0).toFixed(1)}%）`)
    push(`自动化/Bot 提交：${formatNumber(cq.bot_commits || 0)} 次`)
    push(`提交说明平均长度：${(cq.avg_subject_length || 0).toFixed(1)} 字 / ${(cq.avg_subject_words || 0).toFixed(1)} 词`)
    push("")
  }
  const ma = metrics.merge_analysis || {}
  if (ma.total_merges) {
    push("合并分析")
    push(`合并提交总数：${formatNumber(ma.total_merges)} 次（占全部提交 ${(ma.merge_ratio || 0).toFixed(1)}%）`)
    push(`PR 合并：${formatNumber(ma.pr_merges || 0)} 次 / 分支合并：${formatNumber(ma.branch_merges || 0)} 次`)
    ;(ma.merge_by_author || []).forEach((r) => push(`谁做的合并：${r.author}：${formatNumber(r.count)} 次`))
    ;(ma.merge_sources || []).forEach((r) => push(`合并来源分支：${r.branch}：${formatNumber(r.count)} 次`))
    push(`含冲突解决的合并：${formatNumber(ma.conflict_merges || 0)} 次（占合并 ${(ma.conflict_ratio || 0).toFixed(1)}%）`)
    ;(ma.conflict_resolvers || []).forEach((r) => push(`谁解决的冲突：${r.author}：${formatNumber(r.count)} 次`))
    ;(ma.conflict_files || []).forEach((r) => push(`冲突热点文件：${r.file}：${formatNumber(r.count)} 次`))
    push("")
  }
  const ra = metrics.revert_analysis || {}
  if (ra.revert_commits || (ra.bug_prone_files || []).length) {
    push("问题溯源（Revert / Bug 高发）")
    push(`回滚提交：${formatNumber(ra.revert_commits || 0)} 次（${(ra.revert_ratio || 0).toFixed(1)}%）`)
    ;(ra.revert_by_author || []).forEach((r) => push(`谁在回滚救火：${r.author}：${formatNumber(r.count)} 次`))
    ;(ra.reverted_authors || []).forEach((r) => push(`谁的提交被回滚：${r.author}：${formatNumber(r.count)} 次`))
    ;(ra.bug_prone_files || []).forEach((r) => push(`Bug 高发文件：${r.file}：${formatNumber(r.count)} 次`))
    push("")
  }
  const ct = metrics.commit_types || {}
  if ((ct.distribution || []).length) {
    push("提交类型细分（Conventional Commits）")
    ct.distribution.forEach((d) => push(`${COMMIT_TYPE_LABELS[d.type] || d.type}：${formatNumber(d.count)} 次（${d.ratio.toFixed(1)}%）`))
    ;(ct.by_author || []).forEach((row) => {
      const parts = COMMIT_TYPE_ORDER.filter((t) => row[t]).map((t) => `${COMMIT_TYPE_LABELS[t] || t} ${row[t]}`)
      push(`${row.author}：${parts.join("，") || "无"}`)
    })
    push("")
  }
  const ow = metrics.ownership || {}
  if (ow.total_files) {
    push("文件所有权与协作")
    push(`涉及文件：${formatNumber(ow.total_files)} 个`)
    push(`单人文件（知识孤岛）：${formatNumber(ow.single_owner_files || 0)} 个（${(ow.single_owner_ratio || 0).toFixed(1)}%）`)
    push(`多人协作文件：${formatNumber(ow.shared_files || 0)} 个`)
    ;(ow.file_owners || []).forEach((f) => push(`热点文件负责人：${f.file}：${f.owner}（${f.owner_ratio.toFixed(0)}%，参与 ${f.author_count} 人）`))
    ;(ow.collaboration_pairs || []).forEach((r) => push(`协作搭档：${r.pair}：${formatNumber(r.count)} 个文件`))
    push("")
  }
  if (metrics.authors && metrics.authors.length) {
    push("开发者明细")
    metrics.authors.forEach((a) =>
      push(
        `${a.author}：提交 ${formatNumber(a.commits)}（${a.commit_ratio.toFixed(1)}%），新增 ${formatNumber(a.added)}，删除 ${formatNumber(a.deleted)}，活跃天 ${a.active_days}，首提交 ${a.first_commit}，末提交 ${a.last_commit}，最活跃时段 ${a.peak_hour}，日均 ${a.avg_per_active_day.toFixed(1)}`
      )
    )
    push("")
  }
  if (metrics.projects && metrics.projects.length) {
    push("项目明细")
    metrics.projects.forEach((p) =>
      push(`${p.project}：提交 ${formatNumber(p.commits)}，新增 ${formatNumber(p.added)}，删除 ${formatNumber(p.deleted)}，开发者 ${p.authors}，活跃天 ${p.active_days}`)
    )
    push("")
  }
  return lines
}

function buildExportText(commits) {
  const summary = buildSummary(commits)
  const { startDate, endDate } = getCurrentFilterRange()
  const projectNames = [...new Set(commits.map((commit) => commit.project))]
  const repoRows = state.data.repos.filter((repo) => projectNames.includes(repo.name))
  const authorRows = buildAuthorRows(commits)
  const projectRows = groupCount(commits, "project").sort((a, b) => b.count - a.count)
  const weekRows = groupCount(commits, "week_day", ["1", "2", "3", "4", "5", "6", "7"])
  const hourRows = groupCount(commits, "hour", Array.from({ length: 24 }, (_, index) => String(index).padStart(2, "0")))
  const metrics = buildMetrics(commits)

  return [
    "Git 工作量报告",
    "========================================",
    `本地生成时间：${state.data.generated_at}`,
    `导出时间：${new Date().toLocaleString("zh-CN")}`,
    `统计时间范围：${startDate} 至 ${endDate}`,
    `当前仓库筛选：${selectedText(state.selectedProjects, state.data.repos.map((repo) => repo.name))}`,
    `当前开发者筛选：${selectedText(state.selectedAuthors, state.data.authors)}`,
    "",
    "核心汇总",
    `仓库数量：${formatNumber(summary.repoCount)}`,
    `有提交项目数：${formatNumber(summary.activeProjectCount)}`,
    `开发者数量：${formatNumber(uniqueCount(commits, (item) => item.author))}`,
    `提交次数：${formatNumber(commits.length)}`,
    `新增代码行：${formatNumber(summary.added)}`,
    `删除代码行：${formatNumber(summary.deleted)}`,
    `净变化行数：${formatNumber(summary.net)}`,
    `日均提交次数：${summary.dailyCommits.toFixed(1)}`,
    `日均工作时长：${summary.dailyHours.toFixed(1)}h`,
    `每周工作时长：${summary.weeklyHours.toFixed(1)}h`,
    `加班时间占比：${summary.overtimeRatio.toFixed(1)}%`,
    "",
    "仓库信息",
    ...(repoRows.length ? repoRows.map((repo) => `${repo.name}｜分支：${repo.branch}｜${repo.path}`) : ["当前筛选条件下没有数据"]),
    "",
    "项目提交占比",
    ...(projectRows.length ? projectRows.map((row) => `${row.label}：${formatNumber(row.count)} 次`) : ["当前筛选条件下没有数据"]),
    "",
    "开发者工作量",
    ...(authorRows.length
      ? authorRows.map((row) => `${row.author}：提交 ${formatNumber(row.commits)}，新增 ${formatNumber(row.added)}，删除 ${formatNumber(row.deleted)}，工作天数 ${formatNumber(row.dates.size)}`)
      : ["当前筛选条件下没有数据"]),
    "",
    "一周七天提交分布",
    ...weekRows.map((row) => `${weekLabels[row.label] || row.label}：${formatNumber(row.count)} 次`),
    "",
    "24 小时提交分布",
    ...hourRows.map((row) => `${row.label}:00：${formatNumber(row.count)} 次`),
    "",
    ...metricsToTextLines(metrics),
    ...branchOverviewTextLines(),
  ].join("\n")
}

function branchOverviewTextLines() {
  const infos = (state.data.branch_infos || []).filter((b) => b.total)
  if (!infos.length) return []
  const lines = ["分支概览"]
  infos.forEach((info) => {
    lines.push(`${info.project}：共 ${info.total} 条（本地 ${info.local} / 远端 ${info.remote}），已并入 HEAD ${info.merged} 条，未并入 ${info.unmerged} 条，僵尸分支（>90 天）${info.stale} 条`)
    const staleList = (info.branches || []).filter((b) => b.stale).sort((a, b) => b.days_idle - a.days_idle).slice(0, 5)
    staleList.forEach((b) => lines.push(`  最久未动：${b.name}（${b.last_author}，${b.last_date}，闲置 ${b.days_idle} 天）`))
  })
  lines.push("")
  return lines
}

function exportReportText() {
  const commits = getFilteredCommits()
  const text = buildExportText(commits)
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" })
  const { startDate, endDate } = getCurrentFilterRange()
  downloadBlob(blob, `git-workload-report-${startDate}_${endDate}.txt`)
}

function exportReportCsv() {
  const commits = getFilteredCommits()
  const csv = buildExportCsv(commits)
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" })
  downloadBlob(blob, buildTimestampFileName("output", "csv"))
}

function renderOverviewCards(metrics) {
  const ts = metrics.time_span || {}
  const cd = metrics.cadence || {}
  const cc = metrics.code_changes || {}
  const cn = metrics.concentration || {}
  const th = metrics.time_health || {}
  const cq = metrics.commit_quality || {}
  const set = (id, value) => {
    document.getElementById(id).textContent = value
  }
  set("ovActiveDays", ts.active_days || 0)
  set("ovLongestStreak", `${(cd.longest_streak || 0)} 天`)
  set("ovAvgLines", (cc.avg_lines_per_commit || 0).toFixed(1))
  set("ovLargeCommits", cc.large_commits || 0)
  set("ovNightRatio", `${(th.night_ratio || 0).toFixed(1)}%`)
  set("ovWeekendRatio", `${(th.weekend_ratio || 0).toFixed(1)}%`)
  set("ovMergeCommits", cq.merge_commits || 0)
  set("ovBusFactor", cn.bus_factor || 0)
  set("ovGini", (cn.gini || 0).toFixed(2))
  set("ovUniqueFiles", formatNumber(cc.unique_files || 0))
}

function renderMonthlyChart(metrics) {
  const list = (metrics.monthly_trend || []).map((m) => ({ label: m.month, count: m.commits }))
  renderBarChart("monthChart", list, (label) => label)
}

function renderTopFilesTable(metrics) {
  const rows = (metrics.code_changes && metrics.code_changes.top_files) || []
  const tbody = document.getElementById("topFilesTable")
  tbody.innerHTML = rows.length
    ? rows
        .map(
          (r) => `<tr><td>${escapeHtml(r.file)}</td><td>${formatNumber(r.changes)}</td><td>${formatNumber(r.added)}</td><td>${formatNumber(r.deleted)}</td></tr>`
        )
        .join("")
    : '<tr><td colspan="4">当前筛选条件下没有数据</td></tr>'
}

function renderCategoryChart(metrics) {
  const wc = metrics.work_categories || {}
  const list = [
    { label: "Bug 修复", count: wc.bug_fix_commits || 0 },
    { label: "重构优化", count: wc.refactor_commits || 0 },
    { label: "其他", count: wc.other_commits || 0 },
  ]
  renderBarChart("categoryChart", list, (label) => label)
}

function renderHealthChart(metrics) {
  const th = metrics.time_health || {}
  const list = [
    { label: "深夜(22-05)", count: th.night_commits || 0 },
    { label: "周末", count: th.weekend_commits || 0 },
    { label: "工作(09-18)", count: th.worktime_commits || 0 },
    { label: "非工作", count: th.offhours_commits || 0 },
  ]
  renderBarChart("healthChart", list, (label) => label)
}

function renderAuthorDetailTable(metrics) {
  const rows = metrics.authors || []
  document.getElementById("authorDetailTable").innerHTML = rows.length
    ? rows
        .map(
          (a) =>
            `<tr><td>${escapeHtml(a.author)}</td><td>${formatNumber(a.commits)}</td><td>${a.commit_ratio.toFixed(1)}%</td><td>${formatNumber(a.added)}</td><td>${formatNumber(a.deleted)}</td><td>${formatNumber(a.active_days)}</td><td>${a.first_commit}</td><td>${a.last_commit}</td><td>${a.peak_hour}</td><td>${a.avg_per_active_day.toFixed(1)}</td></tr>`
        )
        .join("")
    : '<tr><td colspan="10">当前筛选条件下没有数据</td></tr>'
}

function renderMergePanel(metrics) {
  const ma = metrics.merge_analysis || {}
  const el = document.getElementById("mergePanel")
  if (!ma.total_merges) {
    el.innerHTML = "当前筛选条件下没有合并提交"
    return
  }
  const parts = []
  parts.push(`<div>合并提交总数：<strong>${formatNumber(ma.total_merges)}</strong> 次（占全部提交 ${ma.merge_ratio.toFixed(1)}%）</div>`)
  parts.push(`<div>PR 合并：${formatNumber(ma.pr_merges)} 次 / 分支合并：${formatNumber(ma.branch_merges)} 次</div>`)
  if ((ma.merge_by_author || []).length) {
    parts.push("<h3>谁做的合并</h3><ul>" + ma.merge_by_author.map((r) => `<li>${escapeHtml(r.author)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  if ((ma.merge_sources || []).length) {
    parts.push("<h3>合并来源分支 Top</h3><ul>" + ma.merge_sources.map((r) => `<li>${escapeHtml(r.branch)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  parts.push(`<div>含冲突解决的合并：<strong>${formatNumber(ma.conflict_merges)}</strong> 次（占合并 ${ma.conflict_ratio.toFixed(1)}%）</div>`)
  if ((ma.conflict_resolvers || []).length) {
    parts.push("<h3>谁解决的冲突</h3><ul>" + ma.conflict_resolvers.map((r) => `<li>${escapeHtml(r.author)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  if ((ma.conflict_files || []).length) {
    parts.push("<h3>冲突热点文件</h3><ul>" + ma.conflict_files.map((r) => `<li>${escapeHtml(r.file)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  el.innerHTML = parts.join("")
}

function renderRevertPanel(metrics) {
  const ra = metrics.revert_analysis || {}
  const el = document.getElementById("revertPanel")
  if (!ra.revert_commits && !(ra.bug_prone_files || []).length) {
    el.innerHTML = "当前筛选条件下没有回滚或修复相关数据"
    return
  }
  const parts = []
  parts.push(`<div>回滚提交：<strong>${formatNumber(ra.revert_commits || 0)}</strong> 次（${(ra.revert_ratio || 0).toFixed(1)}%）</div>`)
  if ((ra.revert_by_author || []).length) {
    parts.push("<h3>谁在回滚救火</h3><ul>" + ra.revert_by_author.map((r) => `<li>${escapeHtml(r.author)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  if ((ra.reverted_authors || []).length) {
    parts.push("<h3>谁的提交被回滚</h3><ul>" + ra.reverted_authors.map((r) => `<li>${escapeHtml(r.author)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  if ((ra.bug_prone_files || []).length) {
    parts.push("<h3>Bug 高发文件（被修复提交触碰最多）</h3><ul>" + ra.bug_prone_files.map((r) => `<li>${escapeHtml(r.file)}：${formatNumber(r.count)} 次</li>`).join("") + "</ul>")
  }
  el.innerHTML = parts.join("")
}

function renderTypeChart(metrics) {
  const dist = (metrics.commit_types || {}).distribution || []
  const list = dist.map((d) => ({ label: COMMIT_TYPE_LABELS[d.type] || d.type, count: d.count }))
  renderBarChart("typeChart", list, (label) => label)
  const byAuthor = (metrics.commit_types || {}).by_author || []
  const el = document.getElementById("typeByAuthorPanel")
  if (!byAuthor.length) {
    el.innerHTML = ""
    return
  }
  el.innerHTML =
    "<h3>每位开发者的类型构成</h3><ul>" +
    byAuthor
      .map((row) => {
        const parts = COMMIT_TYPE_ORDER.filter((t) => row[t]).map((t) => `${COMMIT_TYPE_LABELS[t] || t} ${row[t]}`)
        return `<li>${escapeHtml(row.author)}：${parts.join("，") || "无"}</li>`
      })
      .join("") +
    "</ul>"
}

function renderOwnershipPanel(metrics) {
  const ow = metrics.ownership || {}
  const summaryEl = document.getElementById("ownershipSummary")
  const tbody = document.getElementById("ownershipTable")
  const collabEl = document.getElementById("collaborationPanel")
  if (!ow.total_files) {
    summaryEl.innerHTML = "当前筛选条件下没有数据"
    tbody.innerHTML = ""
    collabEl.innerHTML = ""
    return
  }
  summaryEl.innerHTML = `<div>涉及文件：${formatNumber(ow.total_files)} 个 ｜ 单人文件（知识孤岛）：${formatNumber(ow.single_owner_files)} 个（${ow.single_owner_ratio.toFixed(1)}%）｜ 多人协作文件：${formatNumber(ow.shared_files)} 个</div>`
  tbody.innerHTML = (ow.file_owners || []).length
    ? ow.file_owners
        .map((f) => `<tr><td>${escapeHtml(f.file)}</td><td>${escapeHtml(f.owner)}</td><td>${f.owner_ratio.toFixed(0)}%</td><td>${f.author_count}</td></tr>`)
        .join("")
    : '<tr><td colspan="4">没有数据</td></tr>'
  collabEl.innerHTML = (ow.collaboration_pairs || []).length
    ? "<h3>协作最多的搭档（共同改动文件数）</h3><ul>" + ow.collaboration_pairs.map((r) => `<li>${escapeHtml(r.pair)}：${formatNumber(r.count)} 个文件</li>`).join("") + "</ul>"
    : ""
}

function renderBranchPanel() {
  const el = document.getElementById("branchPanel")
  const infos = (state.data.branch_infos || []).filter((b) => b.total)
  const selected = state.selectedProjects
  const visible = infos.filter((b) => !selected.size || selected.has(b.project))
  if (!visible.length) {
    el.innerHTML = "没有分支数据（仓库级统计，不受时间/开发者筛选影响）"
    return
  }
  el.innerHTML = visible
    .map((info) => {
      const parts = []
      parts.push(`<h3>${escapeHtml(info.project)}</h3>`)
      parts.push(`<div>共 ${info.total} 条（本地 ${info.local} / 远端 ${info.remote}）｜ 已并入 HEAD：${info.merged} 条 / 未并入：${info.unmerged} 条 ｜ 僵尸分支（&gt;90 天）：${info.stale} 条</div>`)
      const cats = Object.entries(info.categories || {}).sort((a, b) => (b[1] - a[1]) || (a[0] < b[0] ? -1 : 1))
      if (cats.length) parts.push(`<div>命名类别：${cats.map(([k, v]) => `${escapeHtml(k)} ${v}`).join("，")}</div>`)
      const owners = Object.entries(info.by_author || {}).sort((a, b) => (b[1] - a[1]) || (a[0] < b[0] ? -1 : 1)).slice(0, 8)
      if (owners.length) parts.push(`<div>最后提交人分布：${owners.map(([k, v]) => `${escapeHtml(k)} ${v}`).join("，")}</div>`)
      const staleList = (info.branches || []).filter((b) => b.stale).sort((a, b) => b.days_idle - a.days_idle).slice(0, 5)
      if (staleList.length) {
        parts.push("<div>最久未动分支：</div><ul>" + staleList.map((b) => `<li>${escapeHtml(b.name)}（${escapeHtml(b.last_author)}，${b.last_date}，闲置 ${b.days_idle} 天）</li>`).join("") + "</ul>")
      }
      return parts.join("")
    })
    .join("")
}

function render() {
  syncAuthorChoices()
  syncRepoInfo()
  const commits = getFilteredCommits()
  const summary = buildSummary(commits)
  renderSummary(commits)
  renderBarChart("weekChart", groupCount(commits, "week_day", ["1", "2", "3", "4", "5", "6", "7"]), (label) => weekLabels[label] || label)
  renderBarChart(
    "hourChart",
    groupCount(commits, "hour", Array.from({ length: 24 }, (_, index) => String(index).padStart(2, "0"))),
    (label) => `${label}:00`
  )
  renderPieChart("authorChart", groupCount(commits, "author").sort((a, b) => b.count - a.count).slice(0, 12))
  renderPieChart("projectChart", groupCount(commits, "project").sort((a, b) => b.count - a.count).slice(0, 12))
  renderAuthorTable(commits)
  const metrics = buildMetrics(commits)
  renderOverviewCards(metrics)
  renderMonthlyChart(metrics)
  renderTopFilesTable(metrics)
  renderCategoryChart(metrics)
  renderHealthChart(metrics)
  renderAuthorDetailTable(metrics)
  renderMergePanel(metrics)
  renderRevertPanel(metrics)
  renderTypeChart(metrics)
  renderOwnershipPanel(metrics)
  renderBranchPanel()
  const repoPart = state.selectedProjects.size === 0
    ? `未选择仓库（当前结果为空）`
    : `当前选中 ${summary.repoCount} 个仓库`
  dom.reportMeta.textContent = `本地生成时间：${state.data.generated_at}，${repoPart}，其中 ${summary.activeProjectCount} 个仓库有提交，包含 ${uniqueCount(commits, (item) => item.author)} 位开发者。`
}

async function bootstrap() {
  const response = await fetch("report-data.json")
  state.data = await response.json()
  state.selectedProjects = new Set(state.data.repos.map((repo) => repo.name))
  renderRepoInfo()
  renderPeriodChoices()
  applyPeriod(state.period)
  bindChoices(dom.repoInfoList, state.selectedProjects)
  bindChoices(dom.authorChoices, state.selectedAuthors)
  dom.repoMaster.addEventListener("change", () => {
    if (dom.repoMaster.checked) {
      state.data.repos.forEach((repo) => state.selectedProjects.add(repo.name))
    } else {
      state.selectedProjects.clear()
    }
    render()
  })
  dom.repoClearAll.addEventListener("click", () => {
    state.selectedProjects.clear()
    render()
  })
  dom.repoInvert.addEventListener("click", () => {
    state.data.repos.forEach((repo) => {
      if (state.selectedProjects.has(repo.name)) state.selectedProjects.delete(repo.name)
      else state.selectedProjects.add(repo.name)
    })
    render()
  })
  dom.exportCsv.addEventListener("click", exportReportCsv)
  dom.exportReport.addEventListener("click", exportReportText)
  dom.periodChoices.addEventListener("click", (event) => {
    const button = event.target
    if (!(button instanceof HTMLButtonElement)) return
    state.period = button.dataset.period
    renderPeriodChoices()
    applyPeriod(state.period)
    render()
  })
  ;[dom.startDate, dom.endDate].forEach((element) => {
    element.addEventListener("change", () => {
      state.period = "custom"
      renderPeriodChoices()
      applyPeriod(state.period)
      render()
    })
  })
  render()
}

bootstrap().catch((error) => {
  dom.reportMeta.textContent = `本地报告数据加载失败：${error.message}`
})

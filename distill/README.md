# distill：dsh-hsr-lore 的蒸馏流水线

这套脚本把 biligame 星穹铁道 wiki 的页面变成 `.dsh/skills/dsh-hsr-lore/` 里的知识分片。
**确定性渲染**：脚本只做「抓取 → 结构化 → 渲染」，不做主观改写，所以内容可追溯、可重跑。

## 一条命令跑全流程

```powershell
# 0) 交付前门禁：每个 .ps1 必须 UTF-8 with BOM 且语法可解析（强烈建议每轮先跑）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\check-bom-and-syntax.ps1

# 1) 抓取（可断点续抓，已缓存会跳过；自带节流与重试）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\fetch-missions.ps1

# 2) 解析任务页 -> out\mission-index.json / out\series-index.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\parse-missions.ps1

# 3) 抓取世界观页
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\fetch-worldview.ps1

# 4) 解析世界观页 -> out\worldview-sections.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\parse-worldview.ps1

# 5) 生成 Skill 内容：data\*.json + references\*.md + manifest.yaml
powershell.exe -NoProfile -ExecutionPolicy Bypass -File distill\gen-fragments.ps1

# 6) 同步到全局技能目录（可选但强烈建议，见下节「两份副本」）
$src = 'C:\Users\masha\Desktop\hsr-skill\.dsh\skills\dsh-hsr-lore'
$dst = "$env:USERPROFILE\.dsh\skills\dsh-hsr-lore"
robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP
```

## 两份副本：项目级 vs 用户级（重要）

本 Skill 同时存在两份，**skill 查找顺序是「项目级(100) > 用户级(400)」**：

| 位置 | 作用 | 何时生效 |
| --- | --- | --- |
| `C:\Users\masha\Desktop\hsr-skill\.dsh\skills\dsh-hsr-lore` | 构建工作副本 | 在 `Desktop\hsr-skill` 目录下工作时 |
| `C:\Users\masha\AppData\... → C:\Users\masha\.dsh\skills\dsh-hsr-lore` | **全局副本** | 在**其它任何目录**下工作时 |

**坑**：在 `Desktop\hsr-skill` 里工作时，项目副本会**遮蔽**全局副本 ——
此时改全局副本不生效，改项目副本也不会影响别处。两份必须一起更新。

所以流程是：**改内容 → 跑 `gen-fragments.ps1`（更新项目副本）→ robocopy 同步到全局**。
两边都变完后再用 SHA256 抽查一次，确认没有分叉：

```powershell
Compare-Object (Get-ChildItem $src -Recurse -File | ForEach-Object { $_.FullName.Replace($src,'') + ' ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) `
               (Get-ChildItem $dst -Recurse -File | ForEach-Object { $_.FullName.Replace($dst,'') + ' ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash })
# 无输出 = 两份完全一致
```

> 也可以干脆删掉项目副本、只保留全局那份，这样不存在遮蔽问题；
> 代价是构建工作区少一份可直接预览的副本，且 `distill/` 的重跑结果不会「就地」生效。

## 脚本职责

| 脚本 | 作用 |
| --- | --- |
| `check-bom-and-syntax.ps1` | **交付前门禁**：静态检查每个 `.ps1` 的 BOM 与语法 |
| `fetch-missions.ps1` | 抓「开拓任务」分类全部页面 wikitext → `raw/missions/` |
| `fetch-worldview.ps1` | 抓 P1 世界观页 → `raw/worldview/`（会等任务抓取结束再开始，避免触发风控） |
| `parse-missions.ps1` | 解析任务页模板 → `out/mission-index.json`（任务元数据）、`out/series-index.json`（系列总览页） |
| `parse-worldview.ps1` | 按 `== 标题 ==` 切世界观页 → `out/worldview-sections.json` |
| `story-extract.ps1` | 从任务页正文抽出对话/旁白/场景/选项片段（被 gen 调用） |
| `clean-wikitext.ps1` | 共享的 wikitext 清洗工具（模板、表格、图片链接、HTML 标签） |
| `gen-fragments.ps1` | 渲染 `data/`、`references/`、`manifest.yaml`，并同步 SKILL.md 速查表数字 |
| `curated-terms.json` | 人工策展的术语补充（wiki 上无独立页面的概念），由 gen 并入 `glossary` |

## 目录

```
distill/
├── fetch-missions.ps1
├── fetch-worldview.ps1
├── parse-missions.ps1
├── parse-worldview.ps1
├── story-extract.ps1
├── clean-wikitext.ps1
├── gen-fragments.ps1
├── raw/            # 原始 wikitext 缓存（不属于 Skill 运行时数据）
│   ├── missions/   # 245 个开拓任务页
│   ├── worldview/  # 世界观页
│   └── cat-开拓任务.json
└── out/            # 解析中间产物
    ├── mission-index.json
    ├── series-index.json
    ├── worldview-sections.json
    └── parse-report.txt / worldview-report.txt
```

## 重跑注意（踩过的坑，别再踩）

1. **脚本必须存成 UTF-8 with BOM**。Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 GBK 读，
   中文字面量被拆坏 → 报 `Missing ')' in method call` 之类的语法错误。
   本目录所有 `.ps1` 都已加 BOM；用编辑器改完记得确认 BOM 还在。
2. **`@( … | ConvertFrom-Json )` 是陷阱（踩了两次）**。PS 5.1 里它会把顶层 JSON 数组再包一层，
   变成「1 个元素、而那个元素是 N 元素数组」。
   - 第一次的后果：`worldview-sections.json`（245 条）被当成 1 条，`Where-Object` 过滤失效，
     每个分片都吞下全部条目（表现为「1 条目 / 281KB」）。
   - 第二次的后果：`series-index.json`（22 条）被当成 1 条，章节导语把 22 个系列页当一个对象，
     一条导语渲染成几十行并混入其他章节（chapter-04 出现 176 行）。
   **正确写法**：先用不带 `@()` 的语句取出数组，再 `@()` 包；并在关键处加「长度自检 + 摊平兜底」。
3. **`ConvertTo-Json` 对 `ArrayList` 只序列化第一个元素**，必须先 `.ToArray()`。
4. **改脚本后 BOM 会丢**：某些编辑器/工具写入时会把 UTF-8 BOM 去掉，于是 PS 5.1 按 GBK 读、
   中文字面量被拆坏 → 报假语法错误，**而且脚本可能「跑一半静默停止」不报错退出**。
   本目录所有 `.ps1` 都必须带 BOM；每轮先跑 `check-bom-and-syntax.ps1` 门禁（用 Parser 静态检查，比看退出码可靠）。
5. **任务地区的写法不统一**：有 `雅利洛-Ⅵ-磐岩镇`（带子地点）、`空间站「黑塔」`（词序不同）、
   `雅利洛-Ⅵ、星穹列车`（多地区并列）等变体。
   `gen-fragments.ps1` 里用 `RegionAliases` 表 + 「精确 > 别名 > 前缀 > 包含」优先级处理；
   新增章节时如果出现新变体，加到 `RegionAliases` 里，不要靠模糊匹配猜
   （曾用「黑塔」子串匹配，结果 `chapter-00-herta` 把全部 204 个任务都吃进去了）。
6. **多行字段要压平**：wiki 模板的 `<br>` 会变成换行，直接写进 markdown 会让一条 bullet
   变成几十行（导语块就是这么炸的）。渲染前统一取首个非空行 + 压平空白 + 截断。
7. **站点有 WAF（腾讯 EdgeOne）**：连续快速请求会被拦（HTTP 567 / 返回拦截页）。
   抓取脚本已内置随机 1.4–3.2 秒间隔与指数退避；扩大抓取量时不要去掉节流。
8. **世界观页里有些是战斗机制**：如「命途」页内容是战斗定位（输出/辅助/生存），
   按需求文档第 3 节**不收**。新增世界观页时先看一眼内容性质再登记进 `$PageMap`。
9. **归纳条目必须标冲突**：`curated-terms.json` 里的条目是人工归纳，
   若来源互相矛盾（如「谐乐大典」的周期），**不得择一当定论**——
   必须写进 `conflicts` 字段、渲染成「⚠️ 来源冲突」块、并登记 `pending-review.md`。
10. **不要用启发式规则覆盖权威字段（本轮最大的坑）**。
    主线准入曾写成 `$hasGist -or ($description.Length -gt 20 -and -not $series)`，
    其中 `-not $series` 让后半段对任何"属于系列"的任务失效，
    整个表达式退化成「**wiki 是否已填剧情梗概**」→ 把 4.6 等新版本的 13 个真实开拓任务
    当成非主线静默丢弃（用户一眼就看出 4.6 少了 4 个）。
    **正确做法**：wiki 的 `任务类型=开拓任务` 才是权威判定（实测 217/217），
    区域归属用 `Get-ChapterOf` 二次校验。**编辑进度信号（梗概填没填）绝不能当准入条件。**
11. **覆盖率数字要写清在度量什么**。`204` 算得没错，但它度量的是"wiki 编辑填了多少梗概"，
    不是"主线有多少个"。**算术自洽 ≠ 语义正确** —— 第一轮测试还把这个数当"账目自洽"证据核对过。
12. **新版本内容要单独抽验**。上述 bug 只在「wiki 还没补写梗概」的新内容上暴露，
    老章节梗概齐全全部幸免，所以 7/7 冒烟测试一条都没碰到。加一个"每个版本抽一条"的检查。
13. **改脚本别用 `Set-Content`/正则整文件替换**。本轮用
    `(Get-Content -Raw) -replace ... | Set-Content` 改版本号，
    结果吞掉了一行 `foreach (...) {`，导致 `continue` 落在循环外、脚本**静默跑一半就退出且 exit=0**。
    改脚本用 `edit` 工具做定点替换；改完必须跑 `check-bom-and-syntax.ps1`，
    并留个心眼：**门禁只能查语法，查不出"逻辑被砍掉一半"**，所以关键脚本改完要实际跑一遍看输出行数。
14. **派生文件里的"历史"推导不出来，必须存在源文件里**。
    `data/glossary.json` 每轮被重建（世界观渲染先重置成只含 wiki 条目，策展条目再并入），
    而生成器又把 curated 内容写回 data —— 于是下一轮读到的 data 必然等于 curated 内容，
    **任何"比对上一轮"的留痕逻辑都恒为无差异**（我在这儿耗了很久，确认不可能推导出来）。
    结论：策展条目的 `history` 台账存在 `curated-terms.json` 的 `history` 字段，生成器只负责带过去。
15. **`$existing += ...` 在循环里会重建数组**，导致后面的循环读不到刚追加的元素。
    改用 `System.Collections.ArrayList` + `[void]$x.Add(...)`；
    并且 ArrayList 交给 `ConvertTo-Json` 前**必须 `.ToArray()`**（否则只序列化第一个元素）。
16. **JSON 里不要用半角双引号做中文引述**（`只说"最隆重"`），会截断字符串导致 `ConvertFrom-Json` 报
    `Invalid object passed in, ':' or '}' expected`。用 `『』`。
17. **改完 curated-terms.json 要校验 JSON 合法性**，再跑生成器 —— 否则会在流水线中途炸。

## 未完成 / 可扩展

- **章节切片粒度**：目前一个章节 = 一个 `references/*.md`，翁法罗斯达 277KB。
  若查询时嫌大，可按 `quest:` 条目切成 `<chapter>/<series>.md`，
  并在 `manifest.yaml` 里增加子分片记录（属于结构优化，`knowledge_version` 应 +1.0.0）。
- **跨章节伏笔**：`foreshadowing` 字段目前留空，只标不改，需要人工裁定后按 `UPDATE.md` 补。
- **来源时效校验**：`UPDATE.md` 第 8 节提到的 `last_verified` 尚未落到 manifest。

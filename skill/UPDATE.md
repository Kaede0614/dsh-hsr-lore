# UPDATE.md：dsh-hsr-lore 增量更新与优化协议

本文件是 Skill 的**维护手册**。当用户补充新素材、给出新 wiki 链接、指出错误，或新主线版本发布时，按本协议执行。
核心原则：**知识库不是死文本**——新素材先落 `inbox/`，结构化进 `data/`，按稳定 ID 合并，冲突不覆盖，全部留痕。

## 0. 触发条件

以下任一情况触发本流程：

- 用户明确要求「补充 / 更新 / 优化 dsh-hsr-lore」；
- 用户提供新的 wiki 链接、剧情文本或版本更新信息；
- 用户指出已有条目存在错误；
- 新主线版本发布，需要新增章节分片；
- 定期维护时检查来源可访问性与内容时效性。

## 1. 接收素材（不得直接改知识文件）

把用户给的原始素材**原样**保存到 `inbox/YYYY-MM-DD-<slug>.md`，文件头记录元信息：

```markdown
---
received_at: YYYY-MM-DD
provider: 用户 / 其他来源
source_url: <原始链接>
target_fragment: chapter-03-penacony   # 期望更新哪个分片；不确定写 unknown
kind: new-material | correction | new-version
---

<原始素材正文，逐字保留，不要在这里做整理>
```

规则：

- `inbox/` 是唯一入口；`data/` 与 `references/` 只在下述「合并」步骤被改动；
- 用户口头纠错也要落盘成 inbox 文件（`kind: correction`），这样纠正来源可追溯；
- 素材缺来源 URL 时，在文件里写 `source_url: (用户口述，无链接)`，并在报告里提示该条目 `confidence` 降级为 `medium`。

## 2. 解析与结构化

按 `schemas/knowledge-fragment.schema.json` 把素材整理成条目：

- 新章节 → 新建 fragment ID，延续命名：`chapter-XX-<slug>`（XX 两位序号，如 `chapter-05-xxx`）；
- 已有章节的新内容 → 加入该分片 `entries`，条目 ID 沿用该分片的 `quest:<chapter>-<nn>` 前缀；
- **不要**因为一次补充就重写整个分片文件。

## 3. 按条目 ID 合并（三种情形，处理方式不同）

| 情形 | 处理 |
| --- | --- |
| **新条目** | 直接追加进 `entries` |
| **已有条目被补充/细化** | 更新该条目字段，并把它**旧的** `summary` 压入该条目的 `history` 数组（保留日期与来源），不删除旧内容 |
| **与已有内容冲突** | **不覆盖**。写入 `pending-review.md`，并列「旧版本 + 新版本 + 各自来源」，等用户裁定 |

`pending-review.md` 条目格式：

```markdown
## [待复核] <条目 ID>：<冲突点一句话>

- 发现日期：YYYY-MM-DD
- 触发素材：inbox/YYYY-MM-DD-<slug>.md
- 旧版本：<原文> （来源：<url>）
- 新版本：<原文> （来源：<url>）
- 差异：<具体冲突在哪>
- 状态：待用户确认
```

用户裁定后：按裁定结果更新条目，`history` 留痕，并把该条 pending 标记为已裁定（保留记录，不删）。

## 4. 重建 references 摘要

根据更新后的 `data/*.json` 重新生成或**局部更新**对应 `references/*.md`：

- 摘要单文件控制在 2000 字以内，保留关键对话片段与来源链接；
- `references/` 顶部 YAML frontmatter 必须与 `manifest.yaml` 的记录一致（`id`/`chapter`/`last_updated`/`knowledge_version`/`tags`）；
- 只重建受影响的分片，其他分片不动。

## 5. 更新 manifest.yaml

- 新增/更新分片记录：`id`、`type`、`file`、`data`、`chapter`、`source_urls`、`retrieved_at`、`last_updated`、`version`、`tags`、`entities`、`coverage`；
- 更新全局 `last_updated`；
- **递增 `knowledge_version`**（语义化：补条目 +0.0.1，新增章节/分片 +0.1.0，结构调整 +1.0.0）；
- `tags` 与 `entities` 是查询路由的唯一依据，新增章节必须把地区名、关键角色、事件名写进去。

## 6. 追加 CHANGELOG.md

每次更新必须追加一条（不覆盖历史）：

```markdown
## <knowledge_version> — YYYY-MM-DD

- 触发来源：<用户指令 / inbox 文件 / 版本更新>
- 变更分片：<分片 ID 列表>
- 新增条目：<条目 ID 列表>
- 修订条目：<条目 ID 列表>
- 冲突待复核：<条目 ID 列表，可为「无」>
- 上一版本：<x.y.z>
```

## 7. 报告变更

回答用户时必须说清：

1. 更新了哪些分片、新增了什么内容；
2. 哪些内容进了 `pending-review.md`（以及为什么冲突）；
3. 当前 `knowledge_version` 与 `last_updated`。

## 8. 优化机制

- **用户纠错优化**：纠错不删除旧内容 → 作为新素材进 `inbox/` → 合并 → 更新条目 `confidence` 并在 `CHANGELOG.md` 记录；
- **详细度优化**：可调整 `references` 摘要详细度，但 **`data/` 与条目 ID 必须保持稳定**，避免破坏路由与后续合并；
- **来源校验优化**：定期检查 `source_urls` 可访问性，更新 `last_verified` 字段；页面 404 时在 `pending-review.md` 记录，不静默删除条目；
- **结构优化**：新增章节只需新增分片 + 更新 `manifest.yaml`，**不得重构整个 Skill**。

## 9. 边界（维护时同样适用）

- **不覆盖机制内容**：任何战斗数值、配队、材料、模拟宇宙相关内容都不入库，即使素材里包含；
- **逐字全文不入 Skill**：`data/` 里可保留关键片段，但逐字全文只留在构建缓存或原始 wiki（见第 10 节）；
- **更新需留痕**：没有 `CHANGELOG.md` 记录与 `knowledge_version` 递增的更新视为未完成；
- **不覆盖旧版本**：默认保留历史，只有用户明确确认删除时才移除。

## 10. 构建流水线在哪（重要：本 Skill 可能被装到别处）

本 Skill **自带的知识只够查询**；要**重新抓取/重跑生成**，需要用到一套位于 Skill 目录**之外**的
PowerShell 流水线。它的默认位置是本 Skill 的原始构建工作区：

```
C:\Users\masha\Desktop\hsr-skill\distill\
├── check-bom-and-syntax.ps1   交付前门禁（每个 .ps1 必须 UTF-8 with BOM 且语法可解析）
├── fetch-missions.ps1         抓 wiki「开拓任务」分类全部页面 wikitext
├── fetch-worldview.ps1        抓 P1 世界观页
├── parse-missions.ps1         解析任务页 -> out/mission-index.json
├── parse-worldview.ps1        解析世界观页 -> out/worldview-sections.json
├── story-extract.ps1          从任务正文抽对话/旁白/场景
├── clean-wikitext.ps1         共享的 wikitext 清洗
├── gen-fragments.ps1          生成 data/ + references/ + manifest.yaml（并同步 SKILL.md 速查表）
├── curated-terms.json         人工策展术语（会被并入 glossary）
├── README.md                  流水线文档 + 踩坑清单（**动手前先读它**）
├── raw/                       原始 wikitext 缓存（可删，重抓即可恢复）
├── out/                       解析中间产物
└── reports/                   历次独立测试报告原文
```

**跑全流程**（顺序不能乱，每步先过门禁）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <distill>\check-bom-and-syntax.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <distill>\parse-missions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <distill>\parse-worldview.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <distill>\gen-fragments.ps1
```

**如果该目录不存在**（例如本 Skill 被单独拷到别的机器），有两条路：

1. **只用不更新**：正常查询即可，`inbox/` 仍可收素材，但合并要靠手工编辑 `data/*.json` 与 `references/*.md`；
2. **重建流水线**：按本节的文件清单从原始工作区取回 `distill/`（它不在 Skill 目录内，不会随本 Skill 一起被复制）。

**注意**：`gen-fragments.ps1` 会**覆写** `data/*.json`、`references/*.md`、`manifest.yaml`，
并**只改 SKILL.md 的分片速查表数字、不动其余正文**。
所以手工编辑过 `references/` 的话，重跑生成器会丢失 —— 治本做法是把改动归到 `data/` 或 `curated-terms.json`。

### 10.1 归纳条目的修订台账放在哪（重要）

`data/*.json` 是**派生产物**，每轮由流水线重建（世界观渲染会先把 `glossary.json` 重置成只含 wiki 抓来的条目，
策展条目随后被重新并入）。因此：

- **不要指望从 `data/` 比对出修订历史** —— 生成器每轮都会把策展内容写回 data，
  下一轮读到的必然是同一份内容，**任何比对都恒为「无差异」**（实测确认，别再试）；
- 归纳条目的 `history` 台账**存放在 `distill/curated-terms.json` 源文件里**，
  生成器只负责逐轮原样带进 `data/`；
- **修订归纳条目时**：先改 `curated-terms.json` 里的正文，
  再把**修订前的旧内容**追加到该条目的 `history` 数组（字段：`date` / `summary` / `key_points` / `conflicts` / `source_url` / `note`）。
  规则写在 `curated-terms.json` 的 `_history_rule` 字段里，改之前先读它。

### 10.2 本 Skill 可能有两份副本（改完要同步）

Skill 可能同时存在于**项目级**（`<项目>/.dsh/skills/dsh-hsr-lore`）与**用户级**
（`~/.dsh/skills/dsh-hsr-lore`）。skill 的查找顺序是**项目级优先**，因此在项目目录下工作时
项目副本会**遮蔽**全局副本 —— 只改一份会导致两边分叉，且「改了没生效」。

**约定**：重跑生成器后，把项目副本同步到全局副本（`robocopy <src> <dst> /MIR`），
再用 SHA256 抽查确认两边一致。细节见 `distill/README.md` 的「两份副本」一节。

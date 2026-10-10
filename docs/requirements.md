# 需求文档：星穹铁道剧情理解 Skill（dsh-hsr-lore）

## 1. 目标

创建一个 dsh Skill，命名为 **dsh-hsr-lore**，使 dsh 具备对《崩坏：星穹铁道》游戏内容的系统性理解能力，覆盖主线任务（开拓任务）的剧情脉络、关键角色关系、世界观设定与专有名词体系。Skill 加载后，dsh 应能：

- 准确回答主线剧情相关问题，如“雅利洛-VI 主线讲了什么”“匹诺康尼的谐乐大典是怎么回事”；

- 解释星铁专有术语，如“开拓”“星神”“命途”“令使”“忆域”等；

- 梳理主线任务之间的因果链条与章节承接关系；

- 识别剧情中的关键节点、转折与伏笔；

- 在用户提供新素材、新 wiki 链接或纠错信息时，按更新协议增量维护自身知识库。

## 2. 蒸馏来源

限定为 biligame 星穹铁道 wiki（https://wiki.biligame.com/sr/），内容按 CC BY-NC-SA 4.0 协议提供。优先采集以下页面类别：

| 优先级 | 页面类型     | 典型页面                    | 理由                  |
| --- | -------- | ----------------------- | ------------------- |
| P0  | 开拓任务总览   | 开拓任务                    | 主线章节的权威索引           |
| P0  | 各主线任务详情页 | “混乱行至深处”“于长夜重返大地”等      | 包含对话、旁白、场景描述的完整剧情文本 |
| P1  | 世界观/设定页  | 无名客、星神、命途、派系            | 提供剧情理解的背景框架         |
| P1  | 地点/世界页   | 雅利洛-VI、仙舟「罗浮」、匹诺康尼、翁法罗斯 | 主线舞台的背景信息           |
| P2  | 角色页      | 主要角色的 profile 与剧情关联     | 辅助理解角色动机，但不作为核心蒸馏对象 |

P2 角色页仅提取与主线剧情直接相关的条目，如角色在主线中的关键行为、立场转变，不纳入战斗属性、配队建议等游戏机制内容。

## 3. 蒸馏范围界定

### 必须提取的内容

- **主线任务完整文本流**：从序幕到最新主线的任务名称、章节归属、对话文本（含说话者）、旁白、场景描述、选项（至少第一选项）。

- **剧情结构信息**：每个任务的所属章节/幕、前置任务、在主线中的位置。

- **世界观核心概念**：星神、命途、派系、专有地名与事件名称的释义文本。

- **角色—剧情关联**：主要角色在主线中的登场章节、关键行为、关系变化。

### 明确排除的内容

- 游戏机制类：战斗数值、光锥/遗器推荐、配队攻略、角色晋阶材料、模拟宇宙 buff 等。

- 活动/限时任务，除非与主线剧情有直接继承关系，如开拓续闻中补全主线的部分。

- 社区讨论、评论、攻略建议、版本节奏评价等主观内容。

- 图片、视频等多媒体资源。

## 4. 蒸馏流程

### 阶段一：页面发现与去重

从“开拓任务”页面开始，按章节/幕逐层展开，收集所有主线任务的 wiki 页面链接。同时采集 P1 世界观页面的链接。对收集到的 URL 做去重，建立待蒸馏页面清单。

### 阶段二：文本提取与结构化

对每个页面提取主体内容，过滤 wiki 导航模板、编辑提示、评论区等噪音。输出为结构化 JSON 中间格式，建议字段：

json

{
  "page_title": "任务/页面名称",
  "page_type": "main_quest | worldview | location",
  "chapter": "所属章节/幕",
  "prerequisite": "前置任务名或null",
  "segments": [
    {
      "type": "dialogue | narration | scene | option",
      "speaker": "角色名（仅dialogue）",
      "content": "文本内容"
    }
  ],
  "source_url": "...",
  "retrieved_at": "YYYY-MM-DD",
  "knowledge_version": "1.0.0"
}

对话选项仅保留第一选项，后续选项如涉及剧情分支可标注在 `content` 末尾。

### 阶段三：剧情链构建

将结构化任务数据按章节顺序排列，识别并标注每个任务之间的“承接关系”，包括前置条件、剧情因果。对于跨章节的伏笔或呼应，在蒸馏产出中以注释形式标记，不展开分析。

### 阶段四：生成 dsh-hsr-lore Skill

将结构化数据组织为 dsh Skill 所需的文件结构。Skill 必须支持后续增量更新，而不是一次性死文本。

## 5. Skill 总体设计原则

dsh-hsr-lore 采用“逻辑层与知识层分离、分片化、条目化、可增量更新”的结构。

1. **逻辑层与知识层分离**  
   `SKILL.md` 只放能力概述、查询路由、更新协议入口、引用规范。具体剧情内容放在 `references/` 和 `data/` 中，可独立替换、追加、修订。

2. **分片化**  
   按章节或主题分片，例如 `chapter-03-penacony.md`、`worldview-aeons.md`。每个分片独立更新，避免改动一处牵动全库。

3. **条目化**  
   每个分片内的任务、概念、角色关联都有稳定 ID，例如 `quest:penacony-01`、`concept:aeon`。更新时按 ID 合并，而不是整体重写。

4. **来源可追溯**  
   每个知识条目记录 `source_url`、`retrieved_at`、`version`。回答时可注明来源为 biligame wiki。

5. **冲突不覆盖**  
   新素材与旧内容冲突时，不直接覆盖，写入 `pending-review.md`，保留新旧版本和来源，等待用户确认。

6. **manifest 驱动**  
   查询路由和更新管理基于 `manifest.yaml`，不在 `SKILL.md` 中硬编码全部章节列表。

## 6. Skill 目录结构

Skill 根目录为 `.dsh/skills/dsh-hsr-lore/`，建议结构如下：

text

.dsh/skills/dsh-hsr-lore/
├── SKILL.md
├── UPDATE.md
├── manifest.yaml
├── CHANGELOG.md
├── pending-review.md
├── inbox/
│   └── .gitkeep
├── schemas/
│   └── knowledge-fragment.schema.json
├── data/
│   ├── chapter-00-herta.json
│   ├── chapter-01-jarilo.json
│   ├── chapter-02-luofu.json
│   ├── chapter-03-penacony.json
│   ├── chapter-04-amphoreus.json
│   ├── worldview-aeons.json
│   ├── worldview-paths.json
│   ├── worldview-factions.json
│   └── glossary.json
└── references/
    ├── chapter-index.md
    ├── chapter-00-herta.md
    ├── chapter-01-jarilo.md
    ├── chapter-02-luofu.md
    ├── chapter-03-penacony.md
    ├── chapter-04-amphoreus.md
    ├── worldview-aeons.md
    ├── worldview-paths.md
    ├── worldview-factions.md
    └── glossary.md

## 7. SKILL.md 结构要求

`SKILL.md` 遵循 Agent Skills 规范，YAML frontmatter 必须包含 `name` 和 `description`。建议：

yaml

---

name: dsh-hsr-lore
description: 崩坏星穹铁道主线剧情与世界观的查询、理解与增量维护。当用户询问星铁主线剧情、章节内容、世界观概念、角色剧情关系，或要求补充/更新星铁剧情素材时使用。
whenToUse: 用户提及星铁/星穹铁道/HSR 主线、开拓任务、剧情章节、星神/命途/派系等世界观概念，或要求梳理剧情脉络、补充剧情素材时。

---

正文结构建议不超过 150 行，细节放入 `references/` 和 `UPDATE.md`：

1. **能力概述**  
   说明能回答剧情、世界观、角色剧情关系类问题；不能回答机制、配队、数值、攻略类问题，遇到此类问题应明确拒绝并说明边界。

2. **知识库状态**  
   指示 dsh 先读取 `manifest.yaml`，获取 `knowledge_version`、`last_updated` 和分片列表。

3. **查询路由**  
   根据用户问题中的章节名、角色名、事件名、关键词，匹配 `manifest.yaml` 中分片的 `tags`、`chapter`、`entities`，加载对应 `references/*.md`。例如：
   
   - “雅利洛-VI 主线发生了什么” → 加载 `references/chapter-01-jarilo.md`
   
   - “什么是星神” → 加载 `references/worldview-aeons.md`
   
   - “翁法罗斯的泰坦是什么” → 加载 `references/chapter-04-amphoreus.md`

4. **更新入口**  
   当用户提供新 wiki 链接、新剧情文本、纠错信息，或明确要求“补充/更新 dsh-hsr-lore”时，指示 dsh 按 `UPDATE.md` 执行增量更新流程。

5. **引用规范**  
   回答时注明信息来源为 biligame wiki，不将 wiki 文本作为用户自己的知识陈述。

## 8. 知识分片与数据格式

每个 `references/*.md` 文件顶部使用 YAML frontmatter，便于 manifest 和更新流程解析：

yaml

---

id: chapter-03-penacony
type: chapter
chapter: 第三幕·匹诺康尼
title: 匹诺康尼主线剧情
source_urls:

- https://wiki.biligame.com/sr/...
  last_updated: 2026-10-10
  knowledge_version: 1.0.0
  coverage: 主线任务全量摘要；关键对话片段
  confidence: high
  supersedes: []
  tags: [匹诺康尼, 谐乐大典, 星期日, 知更鸟]

---

正文按任务或概念条目组织，每个条目有稳定 ID：

md

### quest:penacony-01

- 任务名：...
- 前置：...
- 概要：...
- 关键片段：
  - [说话者] ...

对应的 `data/*.json` 保存结构化中间数据，字段与第 4 节一致，并增加 `id`、`tags`、`entities`、`source_urls`。`references/*.md` 是便于 dsh 阅读的摘要视图，`data/*.json` 是便于更新合并的源数据。

## 9. 增量更新与优化机制

这是 dsh-hsr-lore 的核心要求：Skill 不是死文本，而是可通过补充新素材持续更新和优化。

### 9.1 更新触发条件

以下情况应触发更新流程：

- 用户明确要求补充、更新、优化 dsh-hsr-lore；

- 用户提供新的 wiki 链接、剧情文本、版本更新信息；

- 用户指出已有回答或知识条目存在错误；

- 新主线版本发布，需要新增章节分片；

- 定期维护时检查来源可访问性和内容时效性。

### 9.2 更新流程

1. **接收素材**  
   将用户提供的原始素材保存到 `inbox/YYYY-MM-DD-<slug>.md`，保留来源 URL、提供者、时间。不得直接覆盖已有知识文件。

2. **解析与结构化**  
   按 `schemas/knowledge-fragment.schema.json` 解析素材，生成或更新 `data/<fragment-id>.json`。如果素材对应新章节，创建新的 fragment ID，如 `chapter-05-xxx`。

3. **按条目合并**  
   如果目标分片已存在，按稳定 ID 合并：
   
   - 新条目：追加；
   
   - 已有条目更新：更新内容并保留旧版本到 `pending-review.md` 或条目的 `history` 字段；
   
   - 冲突条目：不覆盖，写入 `pending-review.md`，标记新旧来源和差异。

4. **重建 references 摘要**  
   根据更新后的 `data/*.json`，重新生成或局部更新对应 `references/*.md`。摘要控制在 2000 字以内，保留关键对话片段与来源链接。

5. **更新 manifest.yaml**  
   添加或更新分片记录，包括 `id`、`type`、`file`、`data`、`chapter`、`source_urls`、`last_updated`、`version`、`tags`、`coverage`。同时递增 `knowledge_version`。

6. **追加 CHANGELOG.md**  
   记录本次更新：时间、触发来源、变更分片、新增/修订条目、冲突待复核项、新知识库版本。

7. **报告变更**  
   在回答中告知用户：更新了哪些分片、新增了什么、哪些内容进入待复核、当前 knowledge_version。

### 9.3 优化机制

- **用户纠错优化**：用户指出错误时，不直接删除旧内容，而是作为新素材进入 `inbox/`，经合并后更新条目，并在 `CHANGELOG.md` 记录。

- **详细度优化**：可调整 `references` 摘要详细度，但保持 `data` 和条目 ID 稳定，避免破坏路由。

- **来源校验优化**：定期检查 `source_urls` 是否可访问，更新 `last_verified` 字段。

- **结构优化**：新增章节只需添加分片并更新 `manifest.yaml`，无需重构整个 Skill。

## 10. 输出要求

最终产出物为一个完整的 dsh Skill 目录，用户可直接放置于 `~/.dsh/skills/dsh-hsr-lore/` 或项目 `.dsh/skills/dsh-hsr-lore/` 下被 dsh 自动加载。

交付物清单：

- `SKILL.md`：入口文件，含 frontmatter、能力概述、查询路由、更新入口、引用规范；

- `UPDATE.md`：增量更新与优化流程说明；

- `manifest.yaml`：知识分片清单与版本信息；

- `CHANGELOG.md`：更新记录；

- `pending-review.md`：冲突与待复核条目；

- `inbox/`：新素材收件箱；

- `schemas/`：数据结构定义；

- `data/`：结构化 JSON 中间数据；

- `references/`：可读知识分片。

## 11. 验证方式

Skill 完成后，用以下问题做加载与更新冒烟测试：

1. “雅利洛-VI 主线讲了一个什么故事？” → 应能输出该章节核心冲突与关键节点。

2. “匹诺康尼的‘谐乐大典’是什么事件？” → 应能定位到第三幕并给出事件概要。

3. “星神和命途是什么关系？” → 应能加载世界观文件并给出定义式回答。

4. “星铁光锥推荐怎么配？” → 应明确拒绝，并说明该 Skill 不覆盖游戏机制内容。

5. “翁法罗斯主线里‘泰坦’是什么？” → 应能定位到第四幕相关文件并给出释义。

6. “给 dsh-hsr-lore 补充匹诺康尼 2.3 主线素材：<链接>” → 应写入 `inbox/`，更新对应分片，更新 `manifest.yaml`，追加 `CHANGELOG.md`，并报告变更。

7. “之前回答的雅利洛-VI 剧情有误，应该是……” → 应进入 `pending-review.md`，不直接覆盖，记录纠正来源。

## 12. 边界与注意事项

- **版权**：蒸馏产出仅用于个人/研究用途，不得用于商业目的。Skill 中应保留来源声明：biligame wiki，CC BY-NC-SA 4.0。

- **时效性**：主线随版本更新持续扩展。Skill 设计为可增量更新，新增主线时只需添加对应分片并更新 `manifest.yaml`。

- **不覆盖旧版本**：更新时默认保留历史，除非用户明确确认删除。

- **不覆盖机制内容**：任何涉及战斗、配队、数值、攻略的问题，Skill 应明确表示无法回答。

- **逐字全文不入 Skill**：Skill 旨在提供“理解”而非“存档”。逐字对话全文更适合作为独立数据源，Skill 中保留摘要与关键片段即可。

- **更新需留痕**：每次更新必须写入 `CHANGELOG.md`，并更新 `manifest.yaml` 的 `knowledge_version`。

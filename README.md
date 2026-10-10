# dsh-hsr-lore

**简体中文**

> 给 **DeepSeek Harness (dsh)** 用的《崩坏：星穹铁道》主线剧情知识技能（Agent Skill）。
> 把主线剧情、任务因果链与世界观概念蒸馏成**结构化、可增量维护**的知识库，
> 让 AI 答剧情时**引用蒸馏结果**，而不是靠模型记忆复述。

知识全部来自 [biligame 星穹铁道 wiki](https://wiki.biligame.com/sr/)（内容按 **CC BY-NC-SA 4.0** 协议提供）。

---

## 它是什么

一个 dsh **Skill**：加载后，AI 会先读 `manifest.yaml` 拿到版本与分片清单，
再按问题里的章节名/角色名/概念名路由到 `references/` 下的对应分片，然后**基于原文**回答。

**不靠模型记忆**是设计前提：Skill 里写明了「未收录就如实说未收录，不得凭记忆补写剧情」。

### 当前收录规模（`knowledge_version: 0.1.4`）

| 分片 | 内容 | 条目 |
| --- | --- | --- |
| `chapter-00-herta` | 序幕·空间站「黑塔」 | 9 |
| `chapter-01-jarilo` | 第一幕·雅利洛-Ⅵ | 28 |
| `chapter-02-luofu` | 第二幕·仙舟「罗浮」 | 18 |
| `chapter-03-penacony` | 第三幕·匹诺康尼 | 45 |
| `chapter-04-amphoreus` | 第四幕·翁法罗斯 | 66 |
| `chapter-05-paradise` | 第五幕·二相乐园/千星城 | 51 |
| `worldview-aeons` | 星神与令使释义 | 18 |
| `worldview-factions` | 派系与组织释义 | 52 |
| `worldview-locations` | 主线舞台地点释义 | 136 |
| `glossary` | 专有名词表 | 41 |
| **合计** | **10 个分片** | **464** |

主线任务数按 wiki 权威字段 `任务类型=开拓任务` 全量收录，共 **217** 个。

---

## 安装

Skill 目录可以直接拷进 dsh 的技能根：

```powershell
# 全局（推荐）：任何目录下都能用
Copy-Item .\skill\* "$env:USERPROFILE\.dsh\skills\dsh-hsr-lore\" -Recurse -Force

# 或项目级：只在某个项目里生效
Copy-Item .\skill\* "<你的项目>\.dsh\skills\dsh-hsr-lore\" -Recurse -Force
```

dsh 的技能发现规则：`<技能根>/<名字>/SKILL.md`（两层）或技能根下的扁平 `<名字>.md`。
技能根被文件监听，**新增/修改技能不需要重启**。

> **查找优先级**：项目级 `.dsh/skills`（rank 100）**优先于** 用户级 `~/.dsh/skills`（rank 400）。
> 所以同名时项目副本会遮蔽全局副本 —— 只更新一份会导致分叉。

---

## 能问什么

**能答**：主线剧情问答、剧情脉络梳理（前置/后续因果链）、世界观释义（星神/命途/派系/地点）、角色剧情关联、素材维护。

**明确不做**：战斗数值、光锥/遗器推荐、配队攻略、晋阶材料、模拟宇宙 buff 等**游戏机制内容**；
活动/限时任务（除非与主线有直接继承关系）；社区讨论与版本节奏评价；图片视频内容描述。

被问到机制类问题时会**明确拒答**并说明边界。

### 几个真实问答示例

**问**：雅利洛-VI 主线讲了一个什么故事？

> 星穹列车途经雅利洛-Ⅵ，因星轨被「星核」阻塞而被迫停靠，姬子把「开拓」任务交给三月七、丹恒和你。
> 三人降落到雪原，在桑博带领下抵达星球上最后的人类聚落贝洛伯格……
> 最终可可利亚以「大守护者」身份唤醒「造物引擎」，你在命途狭间拔出筑城者的炎枪、受「存护」克里珀的瞥视……
> **布洛妮娅接任「大守护者」**，废除上下层区封锁令。
> *（来源：biligame 星穹铁道 wiki，CC BY-NC-SA 4.0）*

**问**：谐乐大典多久举办一次？（库内存在**来源冲突**）

> 该条目的举办周期在来源中互相矛盾，**两说并列**：
> **说法 A**「一琥珀纪举办一次」—— 游戏内台词，两处佐证（《长日入夜行》广播、《神枪手与智多星》）；
> **说法 B**「一年一度」—— wiki「匹诺康尼」页词条。
> 证据态势：游戏内 3 处 vs wiki 1 处，游戏内占优；但「琥珀纪」与「年」是两套时间单位，故**本 Skill 不裁定**。
> 该冲突已登记 `pending-review.md`，待用户确认。

**问**：星铁光锥推荐怎么配？

> 本 Skill 只覆盖主线剧情与世界观，不包含战斗数值与配队内容，建议查阅 wiki 对应页面。

---

## 设计要点

**逻辑层与知识层分离**：`SKILL.md` 只放能力边界、查询路由、更新入口、引用规范；
具体内容放 `references/`（可读分片）与 `data/`（结构化源数据），两者可独立替换。

**条目化 + 稳定 ID**：每个任务/概念都有稳定 ID（`quest:jarilo-01`、`term:term-40`），
更新时按 ID 合并而不是整体重写。

**来源可追溯**：每个条目带 `source_url`，每轮生成记录 `retrieved_at` / `knowledge_version`。

**冲突不覆盖**：新素材与旧内容冲突时不覆盖，写入 `pending-review.md` 并列两说，等用户裁定。
库里现有两条已声明的冲突（见 `pending-review.md`）。

**诚实标注不确定性**，这是这个项目最在意的一点。三类条目会被显式标注：

| 标记 | 含义 | 运行时要求 |
| --- | --- | --- |
| **〔归纳〕** | 对 wiki **多页**原文的归纳，wiki 上**没有**该独立条目 | 引用时必须说明是归纳、不是 wiki 原文条目 |
| **〔摘要由正文推导〕** | 该任务在 wiki 上**尚无剧情梗概**，摘要由任务正文推导 | 引用时必须说明摘要非 wiki 原文 |
| **⚠️ 来源冲突** | 来源互相矛盾且**尚未裁定** | 必须两说并列、不得自行裁定 |

**逐字全文不入库**：只保留梗概、关键节点、流程与关键片段（节选，每任务约 12 条对话 + 4 条旁白）。

---

## 目录结构

```
.
├── skill/                      ← 拷进技能根的成品（29 个文件 / 4.2 MB）
│   ├── SKILL.md                入口：能力边界、查询路由、更新入口、引用规范
│   ├── UPDATE.md               增量更新与优化协议
│   ├── manifest.yaml           分片清单 + 版本 + 路由用的 tags/entities（路由唯一依据）
│   ├── CHANGELOG.md            逐版本留痕
│   ├── pending-review.md       冲突与待复核条目
│   ├── references/             可读知识分片（11 个 .md）
│   ├── data/                   结构化源数据（10 个 .json）
│   ├── schemas/                数据结构定义（JSON Schema）
│   └── inbox/                  新素材收件箱
├── distill/                    ← 构建流水线（从 wiki 重新抓取/生成）
│   ├── *.ps1                   PowerShell 脚本，见 distill/README.md
│   ├── curated-terms.json      人工策展术语的源文件（含修订台账）
│   ├── README.md               流水线文档 + 踩坑清单（**动手前先读**）
│   └── reports/                历次独立测试报告原文
└── docs/
    └── requirements.md         需求文档（本项目的最初设计）
```

---

## 重新生成 / 更新

需要 Windows PowerShell（脚本用到 `Parser::ParseFile` 与 `robocopy`）。

```powershell
$D = ".\distill"

# 0) 门禁：每个 .ps1 必须 UTF-8 with BOM 且语法可解析
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\check-bom-and-syntax.ps1"

# 1) 抓取 wiki（断点续抓，已缓存跳过，自带节流与退避）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\fetch-missions.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\fetch-worldview.ps1"

# 2) 解析
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\parse-missions.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\parse-worldview.ps1"

# 3) 生成 data/ + references/ + manifest.yaml（写入已安装的 skill 目录）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$D\gen-fragments.ps1"
```

`gen-fragments.ps1` 顶部的 `$SkillDir` 指向技能安装位置，可改。

> **注意**：生成器会**覆写** `data/`、`references/`、`manifest.yaml`，
> 并只同步 `SKILL.md` 里的分片速查表数字与体积（不动其余正文）。
> 手工编辑过 `references/` 的话重跑会丢失 —— 治本做法是把改动归到 `data/` 或 `curated-terms.json`。

**只用不更新**也完全可以：`skill/` 是自包含的，拷过去就能查。
但 `distill/` 不在技能根里，所以从 GitHub clone 的仓库里要更新内容，需要保留整个仓库（含 `distill/`）。

---

## 验证与已知限制

本项目的每一步都有独立子 agent 做黑盒测试，报告原文在 `distill/reports/`。

**已实测通过**：
- 7 问主线剧情冒烟测试（含**故意注入的错误信息**，被正确纠正而非顺从）
- 机制类提问（光锥配装）**明确拒答**，无机制内容泄漏
- 未发现事实错误（12 处高风险角色—事件配对抽查全部与分片原文一致）
- 增量更新协议端到端跑通（素材 → 核实 → 合并 → 留痕 → 版本递增 → CHANGELOG）
- 各分片条目数求和 = `manifest.yaml` 的 `entry_count`（464 = 464）

**已知限制（如实列出）**：
- **未验证**：在项目外的会话中全局技能副本能否独立工作（测试环境限制，见 `CHANGELOG.md` 0.1.4）
- **未验证**：跨会话可复现性、并发场景
- **分片偏大**：`chapter-04-amphoreus.md` 约 275KB。`SKILL.md` 已要求「先 grep 定位再按 offset/limit 读」，
  但更彻底的做法是按系列再切细（属结构优化，需升 `knowledge_version` 主版本）
- **伏笔分析未做**：跨章节伏笔只在条目的 `foreshadowing` 字段留了位置，当前为空
- **wiki 覆盖滞后**：新版本任务常有「剧情梗概」空白，这类条目走「摘要由正文推导」并显式标注
- **`distill/raw/` 不入库**：6.77 MB 的 wiki 原始缓存可由 `fetch-missions.ps1` / `fetch-worldview.ps1` 重建

---

## 版本历史

见 [`skill/CHANGELOG.md`](skill/CHANGELOG.md)。摘要：

| 版本 | 要点 |
| --- | --- |
| 0.1.4 | 增量更新流程实测；补齐「谐乐大典」冲突证据；修好 4 个流水线缺陷 |
| 0.1.3 | **修掉主线准入 bug**：204 → 217 个任务（4.6 从 1 个补到 5 个）；引入「摘要由正文推导」 |
| 0.1.2 | 修 blocker：来源冲突不再写成定论；补「归纳条目必须声明」规范 |
| 0.1.1 | 补 `glossary` 缺失关键词条；修正版本留痕流程 |
| 0.1.0 | 首版：6 幕 204 个任务 + 245 条世界观释义 |

---

## 许可与署名

- **知识内容**（`skill/references/`、`skill/data/`、`skill/manifest.yaml` 中的释义与剧情文本）：
  蒸馏自 [biligame 星穹铁道 wiki](https://wiki.biligame.com/sr/)，
  该站声明「内容按 **CC BY-NC-SA 4.0** 协议提供」。**转载/再分发请保留署名并以相同方式共享，且不得用于商业目的。**
- **《崩坏：星穹铁道》**游戏内容与相关名称、角色、剧情版权归 **米哈游（miHoYo / HoYoverse）** 所有。
- **本仓库的代码**（`distill/*.ps1` 等）：见 [`LICENSE`](LICENSE)。
- **用途**：本项目仅供**个人学习与研究**，非商业用途，与米哈游及 biligame 无隶属或授权关系。
  若权利人认为不妥，请提 issue，我会下架相关内容。

如果这个项目对你有帮助，欢迎提 issue 纠错 —— **纠错会走 `UPDATE.md` 的流程留痕**，不会静默覆盖。

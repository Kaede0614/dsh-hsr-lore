# v0.1.4 — 首版发布

面向 **DeepSeek Harness (dsh)** 的《崩坏：星穹铁道》主线剧情知识技能。

## 内容规模

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

主线任务数按 wiki 权威字段 `任务类型=开拓任务` 全量收录，共 **217** 个，跨 6 幕。

## 安装

```powershell
Copy-Item .\skill\* "$env:USERPROFILE\.dsh\skills\dsh-hsr-lore\" -Recurse -Force
```

## 本版包含

- **Skill 本体**（`skill/`）：`SKILL.md` + `UPDATE.md` + `manifest.yaml` + `CHANGELOG.md` +
  `pending-review.md` + 11 个 `references/*.md` + 10 个 `data/*.json` + JSON Schema + `inbox/`
- **构建流水线**（`distill/`）：PowerShell 脚本，可从 biligame wiki 重新抓取并生成全部内容
- **测试报告**（`distill/reports/`）：3 份独立子 agent 的黑盒测试报告原文
- **需求文档**（`docs/requirements.md`）

## 设计要点

- **逻辑层与知识层分离**：`SKILL.md` 只管能力边界/路由/更新入口/引用规范，内容放 `references/` + `data/`
- **条目化 + 稳定 ID**：`quest:jarilo-01`、`term:term-40`，按 ID 合并式更新
- **冲突不覆盖**：来源矛盾时并列两说并登记 `pending-review.md`，等用户裁定
- **显式标注不确定性**（本项目最在意的一点）：
  | 标记 | 含义 |
  | --- | --- |
  | **〔归纳〕** | 对 wiki 多页原文的归纳，wiki 上没有该独立条目 |
  | **〔摘要由正文推导〕** | 该任务在 wiki 上尚无剧情梗概，摘要由正文推导 |
  | **⚠️ 来源冲突** | 来源互相矛盾且尚未裁定 |
- **明确拒答机制类问题**：战斗数值、光锥/遗器推荐、配队攻略等一律不收录

## 已验证

- 7 问主线剧情冒烟测试通过，含**故意注入的错误信息**（被正确纠正而非顺从）
- 机制类提问明确拒答，无机制内容泄漏
- 未发现事实错误（12 处高风险角色—事件配对抽查全部与分片原文一致）
- 增量更新协议端到端跑通（素材 → 核实 → 合并 → 留痕 → 版本递增 → CHANGELOG）
- 各分片条目数求和 = `manifest.yaml` 的 `entry_count`（464 = 464）

## 已知限制

- **未验证**：在项目外的会话中全局技能副本能否独立工作（测试环境限制）
- **未验证**：跨会话可复现性、并发场景
- `chapter-04-amphoreus.md` 约 275KB，偏大；`SKILL.md` 已要求「先 grep 定位再按 offset/limit 读」
- 跨章节伏笔分析未做（`foreshadowing` 字段已留位，当前为空）
- 新版本任务常有「剧情梗概」空白，这类条目走「摘要由正文推导」并显式标注
- `distill/raw/`（约 6.8MB wiki 原始缓存）未入库，可由抓取脚本重建

## 待裁定（见 `skill/pending-review.md`）

1. **谐乐大典举办周期**：游戏内台词两处写「一琥珀纪举办一次」，wiki 词条写「一年一度」——
   已并列两说、证据态势已核实（游戏内 3 处 vs wiki 1 处），但**未裁定**
2. **归纳条目的尺度**：是否允许 `derived: true` 的人工归纳条目进入知识库

## 许可

- **代码**（`distill/*.ps1`）：MIT，见 [LICENSE](https://github.com/Kaede0614/dsh-hsr-lore/blob/main/LICENSE)
- **知识内容**（`skill/references/`、`skill/data/`）：蒸馏自 [biligame 星穹铁道 wiki](https://wiki.biligame.com/sr/)，
  该站声明内容按 **CC BY-NC-SA 4.0** 协议提供。转载须保留署名、以相同方式共享、**不得用于商业目的**
- **游戏内容**版权归米哈游（miHoYo / HoYoverse）所有
- 本项目仅供个人学习与研究，与米哈游及 biligame 无隶属或授权关系

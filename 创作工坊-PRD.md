# 创作工坊 PRD

版本：原生化重构版  
日期：2026-07-01  
状态：当前开发基线文档  
主线形态：macOS 原生应用  

## 1. 文档目的

本 PRD 是在旧版“创作工坊”产品需求基础上，结合当前已经完成的系统重构重新整理的产品文档。

旧版 PRD 的核心目标仍然成立：创作工坊不是一个简单的 AI 代写工具，而是面向日更作者的本地 AI 写作工作台。当前系统架构已经从“Web 前端 + FastAPI 后端 + Python SQLite 层”重构为“SwiftUI macOS 原生应用 + 本地 SQLite + URLSession 直连 AI API + Keychain 安全存储”。因此，本文档重新定义第二阶段之后的产品范围、系统边界、功能优先级和验收标准。

本文档用于指导后续开发，尤其是：

1. 明确 macOS 原生客户端是主线。
2. 明确旧 Web/FastAPI 路径已经清理，macOS 原生端是唯一主线。
3. 将产品从“能生成文章”升级为“能帮助作者持续提高写作能力的智能写作台”。
4. 把 AI 能力设计为工作流、上下文、反馈和复盘系统，而不是零散按钮。
5. 将 Claude Code / Codex 式的“先理解上下文、再制定计划、再执行并自检”的代理工作方式，转译到长文写作场景。

## 2. 产品概述

### 2.1 产品名称

创作工坊

### 2.2 产品定位

创作工坊是一款面向公众号日更作者的本地 AI 写作工作台。它帮助作者完成从想法、选题、大纲、初稿、修改、诊断、复盘到归档的完整写作流程。

它不是“把想法交给 AI 代写”的工具，而是一个“私人编辑室”：

1. 写前帮作者想清楚。
2. 写中帮作者组织表达。
3. 写后像编辑一样诊断问题。
4. 长期记录作者的风格、弱项和复盘结果。
5. 让 AI 提高反馈密度，但保留作者判断权。



### 2.3 一句话介绍

每天输入一个想法，创作工坊帮助你生成可修改的文章草稿，并通过 AI 诊断、修改建议和复盘记录，持续训练你的个人写作能力。

### 2.4 核心价值


| 价值     | 说明                         |
| ------ | -------------------------- |
| 降低启动难度 | 空白文档变成有方向的写作会话             |
| 保持个人风格 | 通过风格配置和 Few-shot 样本注入作者语气  |
| 提高写作效率 | 代理式初稿、选题、大纲、成稿等流程减少重复劳动   |
| 提升写作能力 | 写作教练诊断问题、给出修改顺序和训练重点       |
| 沉淀个人资产 | 本地保存文章、选题、风格、诊断和后续素材       |
| 本地可控   | 数据默认存本地，API Key 存 Keychain |




## 3. 当前架构定位



### 3.1 架构主线

当前主线已经切换为 macOS 原生架构。

```text
macOS SwiftUI App
  -> WorkshopStore
  -> NativeDatabase.swift
     -> Application Support / CreativeWorkshopMac / creative_workshop.sqlite3
  -> NativePrompts.swift
  -> NativeAIClient.swift
     -> URLSession
     -> OpenAI-compatible /chat/completions
  -> KeychainCredentialStore.swift
     -> macOS Keychain
```



### 3.2 已清理的旧路径

旧 Web/FastAPI/Next/Python 路径已从工作区移除，不再保留兼容入口。

已清理范围：

1. `app/` FastAPI/Python 后端。
2. `src/` Next 前端。
3. `web/` 静态前端。
4. `scripts/` Web/FastAPI/Python 验证脚本。
5. NPM/Next 配置与依赖文件。
6. Python/uv 配置与依赖文件。

保留项：

1. `.env`、`data/`、`exports/` 若在本机仍存在，只作为 `.gitignore` 排除的私有历史数据或临时产物。
2. 原生 App 不再从仓库 `data/` 自动复制旧库，运行时数据库唯一位置是 `~/Library/Application Support/CreativeWorkshopMac/creative_workshop.sqlite3`。



### 3.3 当前原生端已落地能力


| 模块            | 当前状态 | 说明                                                |
| ------------- | ---- | ------------------------------------------------- |
| SwiftUI 原生工作台 | 已落地  | 三栏布局：侧边栏、写作画布、右侧 Inspector                        |
| 本地 SQLite     | 已落地  | 原生 `NativeDatabase.swift` 直接读写                    |
| 模型设置          | 已落地  | Base URL、模型名、API Key                              |
| Keychain      | 已落地  | API Key 保存到 macOS Keychain                        |
| 文章列表          | 已落地  | 侧边栏展示最近文章                                         |
| 选题列表          | 已落地  | 右侧展示待写选题，可使用和生成大纲                                 |
| 素材箱基础管理       | 已落地  | 原生新增、编辑、删除、搜索、类型筛选、加入当前写作、从素材生成选题                 |
| 代理式初稿         | 已落地  | 输入想法后按写作 brief、论点检查、分段成稿、成稿自评四步生成完整草稿，并进入待复核 |
| 生成选题          | 已落地  | 根据想法、方向、素材生成选题                                    |
| 生成大纲          | 已落地  | 根据选题或当前输入生成结构化大纲                                  |
| 大纲成稿          | 已落地  | 根据大纲生成正文                                          |
| 智能上下文包        | 已落地  | `WritingContextBuilder` 汇总当前稿件、素材、风格、最近文章和最近诊断    |
| 智能下一步         | 已落地  | `WritingAdvisorResult` 判断阶段、最大问题、下一步、上下文观察、执行计划和风险提示 |
| 发布物料          | 已落地  | 生成摘要、封面文案、朋友圈文案、标签、小红书版本、封面图提示词                   |
| 局部改写          | 已落地  | 正文编辑器通过 `NSTextView` 桥接读取选区，支持自然、扩写、缩短、加深、画面感、口语化 |
| 全文润色与多版本候选   | 已落地  | 支持全文自然、收紧、加深、口语化和 3 个候选版本                         |
| 待复核工作流        | 已落地  | 大范围生成进入待复核，确认前不覆盖已保存定稿                               |
| 代理运行轨迹与质量门    | 已落地  | 待复核卡片展示代理生成过程，并用 `AgentDraftQualityGate` 标记需要复查的环节        |
| 改稿版本          | 已落地  | `draft_versions` 保存生成/改写前后版本，并在 Inspector 支持差异对比和恢复    |
| 风格库与提示词模板     | 已落地  | 原生设置页支持风格编辑、体裁评价重点、作者雷区和 Prompt 模板编辑                 |
| 诊断-改写闭环       | 已落地  | 写作教练 issue 可定位正文片段，生成候选并人工确认后替换                       |
| 按诊断改全文        | 已落地  | 写作教练可基于最新诊断、当前正文和风格要求生成全文修订候选，并进入待复核                 |
| 写作复盘深化        | 已落地  | 最近复盘详情、文学写作能力趋势和读者视角模拟                                |
| 选题去重          | 已落地  | 新选题写入前过滤与已有选题高度相似的候选                                  |
| 保存文章          | 已落地  | 保存标题、摘要、正文、标签、关联选题                                |
| 统计概览          | 已落地  | 文章数、本周、本月、待写选题、高频方向、连续写作                          |
| 写作教练          | 已落地  | 诊断当前想法、大纲、正文，保存复盘记录                               |
| AI fallback   | 已落地  | 无 API Key 或模型失败时使用本地模拟结果                          |
| 单元测试          | 已落地  | SQLite、模型解码、写作诊断存取测试                              |




### 3.4 当前原生端仍待补齐能力


| 模块         | 优先级 | 说明                               |
| ---------- | --- | -------------------------------- |
| 导入导出       | P1  | JSON 导入导出、Markdown 导出            |
| 流式输出       | P2  | 原生 URLSession 流式解析，实时写入编辑器       |

以下能力已经从本表移出并在原生端落地：风格库编辑、提示词模板编辑、全文润色、多版本候选、恢复改稿前后、归档筛选、版本差异对比、写作教练复盘详情、文学写作能力雷达、读者视角模拟、选题去重、代理式初稿、代理运行轨迹、代理质量门、智能下一步深度观察和诊断驱动全文改稿。




## 4. 用户画像



### 4.1 第一目标用户

当前阶段只服务一个核心用户：工具开发者本人。

用户特征：

1. 经常写公众号或长文。
2. 有大量碎片化想法。
3. 希望借助 AI 提高效率，但不希望文章变成模板文。
4. 更看重个人表达、长期积累和写作能力提升。
5. 能接受本地应用、本地数据库、API Key 配置等工作方式。



### 4.2 典型痛点


| 痛点          | 产品回应                 |
| ----------- | -------------------- |
| 有想法但不知道怎么展开 | 生成选题、大纲、初稿           |
| 空白文档压力大     | 代理式初稿和默认大纲           |
| AI 文章太像模板   | 风格配置、样本注入、写作诊断       |
| 写完不知道哪里不好   | 写作教练给出问题、建议和修改顺序     |
| 灵感和文章没有沉淀   | 本地 SQLite 保存文章、选题、复盘 |
| 不想把数据放云端    | 本地数据库和 Keychain      |




## 5. 产品原则



### 5.1 AI 不替代作者

AI 的职责是提出选项、组织结构、给出反馈和辅助修改。最终判断权属于作者。

### 5.2 先形成可修改的东西

产品优先帮助用户跨过“空白文档”，先生成可修改的草稿，再进入诊断和修改。

### 5.3 从生成工具升级为训练系统

产品不仅要问“这篇文章怎么生成”，还要问“作者下次怎样写得更好”。写作教练、复盘记录、训练重点、作者雷区清单、文学写作能力趋势和读者视角模拟是长期核心。

### 5.4 本地优先，隐私优先

文章、选题、复盘、风格默认保存本地。API Key 不写入普通配置文件，使用 macOS Keychain。

### 5.5 原生体验优先

新的功能只进入 SwiftUI 原生端。旧 Web/FastAPI 路径已移除，不再作为产品形态。

### 5.6 大范围生成必须可复核

代理式初稿、大纲成稿、全文润色和多版本候选都必须保留生成前快照。大范围改动默认进入待复核或版本候选状态，作者确认前不得覆盖已保存的定稿内容；局部改写因为范围小，可以直接应用，但必须进入版本历史并可恢复。

### 5.7 先建模，再成稿

深度写作不能只靠一次 prompt 直出。初稿生成必须先形成写作 brief，检查论点和素材缺口，再分段成稿，最后自我批评和质量门复查。智能下一步也必须像 Claude Code / Codex 一样先给上下文观察、执行计划和风险提示，再建议具体动作。

## 6. 信息架构

当前和目标信息架构如下：

```text
创作工坊
  1. 工作区
     1.1 创作会话
     1.2 写作画布
     1.3 写作教练
  2. 文章
     2.1 最近文章
     2.2 草稿
     2.3 已完成
     2.4 已发布
     2.5 已归档
  3. 待写选题
     3.1 选题列表
     3.2 选题详情
     3.3 使用选题
     3.4 选题生成大纲
  4. 素材箱
     4.1 灵感
     4.2 金句
     4.3 文章片段
     4.4 素材入稿
  5. 风格与提示词
     5.1 风格库
     5.2 Few-shot 样本
     5.3 提示词模板
  6. 复盘
     6.1 单篇诊断
     6.2 最近复盘
     6.3 能力趋势
  7. 设置
     7.1 模型配置
     7.2 Keychain API Key
     7.3 数据库路径
     7.4 导入导出
```



## 7. 核心使用流程



### 7.1 代理式初稿流程

适合日常快速写作。

```text
输入想法
  -> 选择写作方向
  -> 可选输入素材
  -> 生成写作 brief
  -> 论点检查和素材缺口检查
  -> 分段成稿
  -> 成稿自评
  -> 进入待复核
  -> 人工确认或放弃
  -> 写作诊断
  -> 按诊断局部改写或全文改稿
  -> 保存文章
```

验收标准：

1. 想法为空时不能触发生成，并提示“请先输入想法”。
2. 有 API Key 时调用模型接口。
3. 无 API Key 或模型失败时给出本地 fallback 草稿。
4. 生成结果至少能填充标题、正文、摘要或原始输出。
5. 待复核卡片必须展示代理运行轨迹和质量门结果。
6. 未确认待复核版本前，不允许保存为定稿。
7. 保存后文章出现在最近文章中。



### 7.2 步步推进流程

适合需要控制文章方向时。

```text
输入想法
  -> 生成选题
  -> 选择选题
  -> 生成大纲
  -> 编辑大纲
  -> 大纲成稿
  -> 写作诊断
  -> 保存文章
```

验收标准：

1. 生成选题后写入 `topics` 表。
2. 使用选题时带入标题、摘要、方向和默认大纲。
3. 大纲成稿时必须存在选题或当前标题/想法。
4. 文章保存后保留 `related_topic_id`。



### 7.3 写作教练流程

适合提高写作能力。

```text
当前标题/摘要/正文/大纲/想法
  -> 写作诊断
  -> AI 输出结构化诊断
  -> 保存到 writing_reviews
  -> Inspector 展示：
       评分
       一句话诊断
       优点
       优先修改项
       修改顺序
       训练重点
       最近复盘
```

验收标准：

1. 标题、正文、大纲、想法、素材只要有任意有效内容，即可诊断。
2. 有 API Key 时调用模型，要求返回结构化 JSON。
3. 模型返回非 JSON 时保留 `raw_output`。
4. 无 API Key 或调用失败时使用本地规则诊断。
5. 每次诊断都保存为一条 `writing_reviews` 记录。
6. 打开文章时加载该文章最新诊断。



### 7.4 设置流程

```text
打开设置
  -> 填写 API Base URL
  -> 填写模型名称
  -> 填写 API Key
  -> 保存模型设置
  -> Keychain 保存 API Key
  -> SQLite settings 保存 Base URL 和模型名
```

验收标准：

1. API Key 不写入 SQLite 明文字段。
2. 清除 API Key 后 Keychain 中对应记录删除。
3. Base URL 末尾斜杠应归一化。
4. 模型名为空时回退默认模型 `deepseek-v4-pro`。



## 8. 功能需求



### 8.1 工作区与写作画布



#### 当前能力

1. 新建写作会话。
2. 输入写作方向。
3. 输入想法。
4. 输入标题、摘要、正文、大纲、可用素材。
5. 代理式生成初稿。
6. 生成选题。
7. 生成大纲。
8. 大纲成稿。
9. 写作诊断。
10. 保存文章。



#### 后续增强

1. 自动保存当前编辑状态。
2. 支持生成过程中的取消操作。
3. 支持更完整的正文、大纲、素材多面板编辑布局。
4. 支持代理步骤的单步重跑，例如只重跑论点检查或分段成稿。



### 8.2 文章管理



#### 当前能力

1. 展示最近文章。
2. 打开文章到编辑器。
3. 保存文章为草稿。
4. 保存文章和选题关联。



#### 目标能力

1. 按状态筛选：草稿、已完成、已发布、已归档、可二次改写。
2. 按标签筛选。
3. 按时间筛选。
4. 关键词搜索标题、摘要、正文。
5. 支持复制 Markdown。
6. 支持导出 Markdown。
7. 支持删除确认。
8. 支持发布数据录入：阅读、点赞、在看、分享、评论、自评分。



### 8.3 选题池



#### 当前能力

1. 根据想法生成选题。
2. 选题字段包括标题、方向、核心观点、目标读者、说明、角度、情绪、推荐指数、状态、标签。
3. 使用选题带入当前写作会话。
4. 根据选题生成大纲。
5. 右侧 Inspector 展示待写选题。



#### 目标能力

1. 选题独立列表页。
2. 选题搜索和状态筛选。
3. 编辑选题。
4. 删除选题。
5. 从素材生成选题。
6. 标记选题为写作中、已完成、已放弃。



### 8.4 素材箱



#### 当前状态

数据表 `ideas` 和原生素材箱 UI 已落地。当前支持新增、编辑、删除、搜索、类型筛选、加入当前写作、从素材生成选题，并会在加入当前写作或生成选题后标记素材已使用。

#### 目标能力

1. 标签筛选。
2. 将素材扩写成公众号段落。
3. 将素材改写成更有情绪的表达。
4. 保存文章后回写素材关联。
5. 素材和文章、选题之间的关联详情页。



#### 素材类型

1. 灵感。
2. 金句。
3. 文章片段。

分类原则：类型保持少，标签保持灵活。

### 8.5 风格库



#### 当前能力

1. 原生数据库包含 `style_profiles` 表。
2. 默认风格会自动种子写入。
3. 设置页支持风格列表、新建风格、编辑风格、设置默认风格、样本文本维护。
4. 风格档案支持体裁标签 `genre` 和体裁评价重点 `genre_focus`。
5. 风格档案支持作者雷区清单 `known_pitfalls`，可从历史复盘归纳候选，作者确认后才写入。
6. 选题、大纲、初稿、成稿、全文润色、局部改写、写作诊断、智能下一步、发布物料等工作流会按写作方向优先匹配体裁化风格，未命中时回退默认风格。
7. Prompt 中会注入风格描述、体裁评价重点、作者雷区和样本文本；样本优先来自最近同体裁历史文章，人工 `sample_texts` 作为补充。



#### 目标能力

1. 删除风格。
2. 风格对比生成。
3. 根据用户多次修改结果提取风格偏好。
4. 当作者雷区数量增长后，可考虑把 `known_pitfalls` 从 JSON 字段拆成独立表。



#### 默认风格

```text
语言：中文，通俗易懂，有个人表达感
语气：真诚、克制、略带感慨，但不鸡汤
结构：从现实痛点切入，再讲观察，再给方法或感悟
禁忌：不要标题党，不要培训腔，不要营销腔，不要堆砌概念
喜欢的标题：自然、克制、有思考感
不喜欢的标题：夸张、焦虑、低俗、过度反差
```



### 8.6 写作教练

写作教练是原生化重构后的新增核心能力。它代表产品从“生成工具”转向“写作能力训练系统”。

#### 输入

1. 当前标题。
2. 当前摘要。
3. 当前正文。
4. 当前大纲。
5. 当前想法。
6. 写作方向。
7. 当前体裁化风格。
8. Few-shot 样本。
9. 最近一次历史诊断摘要。
10. 作者雷区清单。



#### 输出

```json
{
  "summary": "对当前稿件的一句话诊断",
  "overall_score": 72,
  "strengths": ["已经做得比较好的地方"],
  "issues": [
    {
      "dimension": "开头/结构/观点/素材/表达/节奏/风格",
      "severity": "高/中/低",
      "excerpt": "可选，引用一小段原文",
      "problem": "问题是什么",
      "suggestion": "下一步怎么改"
    }
  ],
  "revision_plan": ["第一步怎么改", "第二步怎么改"],
  "training_focus": ["接下来最该训练的写作能力"],
  "style_notes": ["与作者个人风格有关的观察"],
  "resolved_from_last": ["本次判定已经解决的历史问题"]
}
```



#### 产品要求

1. 诊断不直接重写全文。
2. 优先指出最影响阅读的问题。
3. 每个问题必须有可执行建议。
4. 保留作者个人表达，不鼓励营销腔。
5. 可以诊断半成品，但要提示当前稿件阶段。
6. 诊断结果必须保存，供长期复盘。
7. 如果 issue 的 `excerpt` 能在正文中定位，必须支持一键生成定点改写候选。
8. 内容自上次诊断后没有变化时，必须先提示作者确认，避免空转。
9. 历史诊断需要区分“已解决”和“仍未解决/新增”。
10. 写作教练必须提供“按诊断改全文”入口：基于最新诊断、当前正文、当前风格和上下文包生成一版完整修订稿。
11. “按诊断改全文”属于大范围改动，结果必须进入待复核，不得直接保存为定稿。



### 8.7 润色与局部改写



#### 当前状态

局部改写和全文润色均已在原生端落地。正文编辑器使用 AppKit `NSTextView` 桥接读取选区，调用 `RewriteResult` 生成替换片段，并只替换当前选中区域。全文润色支持“全文自然、全文收紧、全文加深、全文口语”四种模式。

大范围生成动作（代理式初稿、大纲成稿、全文润色）会保存 `DraftSnapshot` 前后版本并进入待复核状态；确认前不得覆盖已保存定稿。正文工具栏的“生成 3 个候选”会基于当前正文生成三个全文候选版本，写入 `draft_versions`，作者可在右侧版本列表中对比差异并选择恢复后应用。

#### 目标能力

全篇操作：

1. 润色。
2. 减少 AI 味。
3. 恢复润色前正文。
4. 生成 3 个候选版本。
5. 改开头。
6. 改结尾。
7. 续写。

局部操作：

1. 选中自然。
2. 选中扩写。
3. 选中缩短。
4. 选中加深。
5. 增强画面感。
6. 改成口语化。

多版本操作：

1. 生成 3 个候选版本。
2. 查看版本差异。
3. 恢复改写前或改写后。

验收标准：

1. 改写必须保留原意。
2. 局部改写只替换选中区域。
3. 模型失败时使用本地 fallback，仍必须只替换选中区域。
4. 等待模型期间正文发生变化时，不覆盖原文，提示重新选择。
5. 全文润色类操作每次改写前必须保留可恢复版本。
6. 多版本候选不直接覆盖当前正文，必须由作者选择后应用。



### 8.8 发布物料



#### 当前能力

1. 生成公众号摘要。
2. 生成封面文案。
3. 生成朋友圈文案。
4. 生成标签。
5. 生成小红书版本。
6. 生成封面图提示词。
7. 保存到本地 `publish_assets` 表。
8. 在右侧 Inspector 展示并支持单项复制。



#### 目标能力

1. 支持编辑发布物料后保存。
2. 支持多版本发布物料对比。
3. 支持将摘要和标签一键写回文章。
4. 支持按平台导出发布清单。

验收标准：

1. 每项可单独复制。
2. 文案保持作者语气。
3. 不硬广，不标题党。
4. 能从当前标题、摘要、正文生成。



### 8.9 复盘与统计



#### 当前能力

1. 文章总数。
2. 已发布数。
3. 本周文章数。
4. 本月文章数。
5. 待写选题数。
6. 高频方向。
7. 连续写作天数。
8. 最近写作诊断。
9. 最近复盘列表详情。
10. 维度趋势条形雷达。
11. 读者视角模拟。



#### 目标能力

1. 最近 30 天写作趋势。
2. 更完整的常见问题维度统计。
3. 训练重点出现频率。
4. 不同写作方向的产出数量。
5. 选题转化率。
6. 素材使用率。
7. 文章二次改写建议。



### 8.10 代理式智能写作链路

代理式智能写作链路是本产品区别于普通 AI 写作按钮的核心能力。它参考 Claude Code / Codex 的工作方式：先理解上下文，再提出计划，然后执行，最后暴露运行轨迹和风险，让作者可以审查过程，而不是只看结果。

#### 当前能力

1. 代理式初稿：`NativeAIClient.agentDraft(...)` 按 writing brief、argument check、section draft、draft critique 四步串行执行。
2. 写作 brief：明确工作标题、核心问题、核心主张、目标读者、段落规划和素材用法。
3. 论点检查：先检查主张是否空泛、素材是否缺口明显、哪些段落需要补证据或场景。
4. 分段成稿：基于 brief 和论点检查结果生成正文，而不是直接一次性展开。
5. 成稿自评：生成后给出 self check，提示风险和复查重点。
6. 代理运行轨迹：待复核卡片展示 brief、论点检查、分段摘要和自我批评。
7. 代理质量门：`AgentDraftQualityGate` 检查 brief、论点、分段、批评和自检是否足够完整。
8. 智能下一步：输出上下文观察、执行计划和风险提示，不只给一个按钮建议。
9. 诊断驱动全文改稿：`improveDraftFromReview` 把最近写作诊断转化为一版完整修订候选。

#### 产品要求

1. 代理链路每一步都必须使用结构化模型，解析失败时有 fallback，不能让主流程中断。
2. 代理 trace 面向作者展示时要简洁，只展示写作判断，不展示底层请求细节或 API Key。
3. 质量门不替作者裁决文章好坏，只提示“哪些生成步骤可能信息不足，需要复查”。
4. 代理式初稿和按诊断改全文都必须进入待复核。
5. 后续若要长期复盘代理过程，可新增持久化 `agent_runs`；当前阶段 trace 只作为待复核运行期上下文。



## 9. AI 系统设计



### 9.1 模型接口

原生端使用 OpenAI-compatible `/chat/completions` 接口。

`NativeAIClient` 负责按业务工作流组装调用，实际请求、JSON 清洗解析、fallback、耗时统计和输入输出摘要统一收口到 `AIWorkflowRunner`。

默认配置：

```text
API Base URL: https://api.deepseek.com
Model: deepseek-v4-pro
Stream: false
Temperature: 0.75
```

后续需要支持：

1. DeepSeek。
2. OpenAI。
3. Claude 兼容代理。
4. LM Studio 本地 OpenAI-compatible 服务。
5. 按任务选择模型。



### 9.2 结构化输出原则

所有核心 AI 工作流都应优先要求 JSON 输出。


| 工作流       | 输出模型                                      |
| -------- | ----------------------------------------- |
| 代理式初稿    | `AgentDraftResponse` / `AgentDraftTrace`  |
| 写作 brief  | `WritingBriefResult`                      |
| 论点检查     | `ArgumentCheckResult`                     |
| 分段成稿     | `SectionDraftResult`                      |
| 成稿自评     | `DraftCritiqueResult`                     |
| 生成选题     | `TopicPayload[]`                          |
| 生成大纲     | `OutlineResult`                           |
| 大纲成稿     | `DraftResult`                             |
| 全文润色     | `DraftResult`                             |
| 按诊断改全文   | `DraftResult`                             |
| 局部改写     | `RewriteResult`                           |
| 写作诊断     | `WritingReviewResult`                     |
| 智能下一步    | `WritingAdvisorResult`                    |
| 生成后自检    | `DraftSelfCheckResult`                    |
| 代理质量门    | `AgentDraftQualityGate`                   |
| 作者雷区归纳   | `PitfallSummaryResult`                    |
| 读者视角模拟   | `ReaderPerspectiveResult`                 |
| 发布物料     | `PublishAssetsResult`                     |


模型返回非 JSON 时：

1. 初稿和大纲保留 `raw_output`。
2. 写作诊断保留 `raw_output`，并展示“模型原始诊断”。
3. 不直接丢弃内容。
4. 不覆盖用户已有正文。



### 9.3 上下文包设计

当前已经抽象 `ContextPackage`，统一管理 AI 请求输入。`WritingContextBuilder` 负责从当前稿件、素材、风格档案、最近文章、最近诊断和作者雷区中构建上下文；`WritingContextPackage` 保留为 `ContextPackage` 的兼容别名。

```text
ContextPackage
  article:
    title
    summary
    content
    outline
  session:
    idea
    direction
    selectedTopic
    selectedMaterials
  style:
    profile
    sampleTexts
    forbiddenExpressions
  memory:
    recentReviews
    commonIssues
  constraints:
    outputSchema
    maxLength
    language
```

目标：

1. 不同按钮共享上下文构建逻辑。
2. 避免 Prompt 到处拼字符串。
3. 支持体裁化风格、作者雷区和最近诊断记忆注入。
4. 支持 token 预算和样本截断。
5. 支持后续模型路由。



### 9.4 AI 调用记录

当前已有 `ai_calls` 表记录：

1. endpoint。
2. model。
3. elapsed_ms。
4. success。
5. error。
6. input_summary。
7. output_summary。
8. created_at。

后续建议扩展：

1. request_hash。
2. token_usage。
3. cost_estimate。
4. linked_article_id。
5. linked_review_id。



### 9.5 代理式初稿工作流

`quickDraft()` 不再是一次请求直出正文，而是调用 `NativeAIClient.agentDraft(...)` 串接四个结构化步骤：

```text
writingBrief
  -> argumentCheck
  -> sectionDraft
  -> draftCritique
  -> DraftResult
  -> draftSelfCheck
  -> PendingDraftReview
```

设计要求：

1. `writingBrief` 先明确核心问题、核心主张、目标读者、段落规划和素材策略。
2. `argumentCheck` 检查论点是否空泛、素材是否缺位、哪些地方需要补场景。
3. `sectionDraft` 基于前两步产出正文，避免一次性长输出失控。
4. `draftCritique` 对成稿进行自我批评，为待复核提供复查线索。
5. `agentDraftTrace` 映射为作者可读的“代理运行轨迹”。
6. `AgentDraftQualityGateEvaluator` 对 trace 和 `draftSelfCheck` 做轻量质量门检查。
7. 最终正文进入 `finalizeGeneratedDraft(...)`，默认 `review_status = pending`。



### 9.6 智能下一步工作流

智能下一步不是“推荐一个按钮”，而是当前稿件的代理式调度器。它必须输出：

1. `stage`：当前处于想法、选题、大纲、初稿、改稿、发布等哪个阶段。
2. `main_problem`：当前最影响继续推进的问题。
3. `next_action`：最推荐的下一步。
4. `suggested_actions`：可执行动作列表。
5. `focus_area`：本轮最该训练的能力。
6. `context_findings`：3～5 条上下文观察。
7. `execution_plan`：2～5 步执行计划。
8. `risk_notes`：当前直接生成、直接润色或直接发布的风险。

这些结果必须保存到 `writing_advisor_runs`，供后续复盘和 Inspector 展示。



### 9.7 诊断驱动全文修订

`improveDraftFromReview(...)` 将最近一次 `WritingReview` 转化为完整改稿候选。它和局部定点改写不同，目标是把诊断中的结构、素材、表达和风格问题统一落实到全文。

约束：

1. 必须读取当前正文、最近诊断、当前风格、作者雷区和上下文包。
2. 输出仍是 `DraftResult`，进入待复核。
3. 不直接保存文章，不覆盖已确认定稿。
4. 模型失败时使用 `NativeFallbacks.improveDraftFromReview(...)`，保证工作流可走通。



## 10. 数据模型



### 10.1 style_profiles

```sql
id                    INTEGER PRIMARY KEY
name                  TEXT NOT NULL
language_style        TEXT
tone                  TEXT
structure_preference  TEXT
favorite_expressions  TEXT
forbidden_expressions TEXT
sample_texts          TEXT
title_style_like      TEXT
title_style_dislike   TEXT
is_default            INTEGER DEFAULT 0
genre                 TEXT
genre_focus           TEXT
known_pitfalls        TEXT
created_at            TEXT
updated_at            TEXT
```



### 10.2 articles

```sql
id                    INTEGER PRIMARY KEY
title                 TEXT
content               TEXT
summary               TEXT
status                TEXT DEFAULT '草稿'
type                  TEXT
tags                  TEXT
self_score            INTEGER
published_at          TEXT
read_count            INTEGER DEFAULT 0
like_count            INTEGER DEFAULT 0
wow_count             INTEGER DEFAULT 0
share_count           INTEGER DEFAULT 0
comment_count         INTEGER DEFAULT 0
related_material_ids  TEXT
related_topic_id      INTEGER
genre                 TEXT
created_at            TEXT
updated_at            TEXT
```



### 10.3 ideas

```sql
id                  INTEGER PRIMARY KEY
title               TEXT
content             TEXT NOT NULL
type                TEXT DEFAULT '灵感'
tags                TEXT
used                INTEGER DEFAULT 0
related_article_id  INTEGER
created_at          TEXT
updated_at          TEXT
```



### 10.4 topics

```sql
id                    INTEGER PRIMARY KEY
title                 TEXT NOT NULL
direction             TEXT
core_viewpoint        TEXT
target_reader         TEXT
description           TEXT
angle                 TEXT
emotion               TEXT
score                 INTEGER DEFAULT 3
status                TEXT DEFAULT '待写'
tags                  TEXT
related_material_ids  TEXT
created_at            TEXT
updated_at            TEXT
```



### 10.5 settings

```sql
id          INTEGER PRIMARY KEY
key         TEXT UNIQUE
value       TEXT
created_at  TEXT
updated_at  TEXT
```



### 10.6 ai_calls

```sql
id                INTEGER PRIMARY KEY
endpoint          TEXT
style_profile_id  INTEGER
material_ids      TEXT
model             TEXT
elapsed_ms        INTEGER
success           INTEGER
error             TEXT
input_summary     TEXT
output_summary    TEXT
created_at        TEXT
```



### 10.7 writing_reviews

```sql
id              INTEGER PRIMARY KEY
article_id      INTEGER
title_snapshot  TEXT
summary         TEXT
overall_score   INTEGER
strengths       TEXT
issues          TEXT
revision_plan   TEXT
training_focus  TEXT
style_notes     TEXT
raw_output      TEXT
model           TEXT
resolved_from_last TEXT
reviewed_snapshot  TEXT
created_at      TEXT
```



### 10.8 prompt_templates

```sql
id             INTEGER PRIMARY KEY
key            TEXT UNIQUE NOT NULL
name           TEXT NOT NULL
system_prompt  TEXT NOT NULL
user_template  TEXT NOT NULL
is_default     INTEGER DEFAULT 1
created_at     TEXT
updated_at     TEXT
```



### 10.9 draft_versions

```sql
id              INTEGER PRIMARY KEY
article_id      INTEGER
title_snapshot  TEXT
action          TEXT
note            TEXT
before_title    TEXT
before_summary  TEXT
before_content  TEXT
after_title     TEXT
after_summary   TEXT
after_content   TEXT
created_at      TEXT
review_status   TEXT DEFAULT 'confirmed'
```



### 10.10 writing_advisor_runs

```sql
id                 INTEGER PRIMARY KEY
article_id         INTEGER
stage              TEXT
main_problem       TEXT
next_action        TEXT
reason             TEXT
suggested_actions  TEXT
focus_area         TEXT
context_findings   TEXT
execution_plan     TEXT
risk_notes         TEXT
raw_output         TEXT
model              TEXT
created_at         TEXT
```

说明：

1. `context_findings` 保存智能下一步的上下文观察。
2. `execution_plan` 保存建议执行顺序。
3. `risk_notes` 保存当前直接推进可能带来的风险。
4. 当前 schema version 为 5。



### 10.11 运行期代理结构

以下结构目前不独立建表，作为生成后的待复核上下文存在：

1. `AgentDraftTrace`：记录 writing brief、论点检查、分段摘要和成稿批评。
2. `AgentDraftQualityGate`：基于 trace 和生成后自检得到的质量门结果。
3. `PendingDraftReview.agentTrace`：把代理运行轨迹挂到本次待复核版本上。

若后续需要跨文章复盘代理运行质量，再新增持久化 `agent_runs` / `agent_steps`，不在当前阶段提前拆表。



## 11. 原生界面要求



### 11.1 主窗口

采用 macOS 原生三栏结构：

```text
Sidebar
  -> 工作区入口
  -> 最近文章

Composer
  -> 创作会话
  -> 写作画布
  -> 标题/摘要/正文/大纲/素材

Inspector
  -> 运行上下文
  -> 写作教练
  -> 统计
  -> 待写选题
```



### 11.2 设计原则

1. 桌面优先，不照搬移动端。
2. 保持工具型产品的密度和可扫描性。
3. 常用动作放在 toolbar 和画布顶部。
4. 诊断、统计、选题放在 Inspector，避免挤压写作画布。
5. 侧边栏保持原生 source list 形态。
6. 长文本区域稳定，不因内容变化跳动。



### 11.3 空状态

每个核心区域都应有空状态：

1. 无文章：提示新建或输入想法。
2. 无选题：提示生成选题。
3. 无诊断：提示运行写作诊断。
4. 无 API Key：提示可使用本地模拟，但建议配置模型。



## 12. 非功能需求


| 类型    | 要求                   |
| ----- | -------------------- |
| 启动    | App 冷启动后 3 秒内可看到主窗口  |
| 本地读写  | 常规保存/读取应小于 1 秒       |
| AI 调用 | 默认超时 90 秒，有明确状态提示    |
| 失败处理  | AI 失败时不清空用户已有内容      |
| 隐私    | API Key 只进入 Keychain |
| 数据    | 用户文章、选题、诊断默认保存本地     |
| 可维护性  | 原生端不依赖 FastAPI       |
| 可测试性  | 数据层和模型解码必须有 XCTest   |
| 可迁移性  | SQLite schema 通过 `PRAGMA user_version` 和 `ensureColumns()` 原地迁移 |




## 13. 验收标准



### 13.1 P0 验收

P0 代表“原生写作闭环可用”。

1. App 可通过 `./script/build_and_run.sh` 构建并启动。
2. 无需启动 FastAPI 或 npm。
3. 可配置 Base URL、模型和 API Key。
4. API Key 保存到 Keychain。
5. 输入想法后可运行代理式初稿流程。
6. 可生成选题。
7. 可生成大纲。
8. 可大纲成稿。
9. 可保存文章。
10. 可运行写作诊断。
11. 写作诊断保存到本地数据库。
12. 可管理素材箱并将素材加入当前写作。
13. 可生成发布物料并保存到本地数据库。
14. 可在正文中选中片段并执行局部改写。
15. 无 API Key 时 fallback 仍可走通流程。
16. 代理式初稿的待复核卡片可展示运行轨迹和质量门。
17. `swift test --disable-sandbox --package-path macos/CreativeWorkshopMac` 通过。



### 13.2 P1 验收

P1 代表“原生主工作台补齐高频写作能力”。

1. 原生风格库编辑完整可用（已满足）。
2. 原生提示词模板编辑完整可用（已满足）。
3. 原生素材 AI 辅助完整可用（已满足）。
4. 原生全文润色、多版本改写和恢复润色前正文完整可用（已满足）。
5. 原生归档筛选完整可用（已满足）。
6. 工作区不再保留 Web/FastAPI/Next/Python 兼容路径（已满足；`data/`、`exports/` 若本机存在仅为忽略的历史归档，不参与运行）。
7. 原生导入导出完整可用（后续待做）。



### 13.3 P2 验收

P2 代表“智能写作台成型”。

1. 支持跨文章复盘洞察和最近复盘详情（已满足当前阶段需求）。
2. 支持写作能力趋势（已满足，当前为维度条形趋势）。
3. 支持诊断-改写闭环、诊断记忆、防空转、作者雷区和读者视角模拟（已满足）。
4. 支持版本差异对比和待复核工作流（已满足）。
5. 支持 Claude Code / Codex 式智能下一步：上下文观察、执行计划、风险提示和建议动作（已满足）。
6. 支持代理式初稿：writing brief、论点检查、分段成稿、成稿自评、运行轨迹和质量门（已满足）。
7. 支持按最新写作诊断改全文，并进入待复核（已满足）。
8. 支持模型路由（后续待做）。
9. 支持流式输出（后续待做）。
10. 支持根据作者修改行为优化风格记忆（后续待做）。
11. 支持完整打包、签名、公证和自动更新预案（后续待做）。



## 14. 开发路线图



### 阶段 A：原生闭环稳定

状态：基本完成。

目标：

1. SwiftUI 主窗口可用。
2. 本地 SQLite 可用。
3. AI API 直连可用。
4. Keychain 可用。
5. 文章、选题、大纲、成稿、写作诊断可用。
6. 单元测试覆盖关键数据链路。



### 阶段 B：补齐高频 P1 能力

状态：多数完成，导入导出待做。

目标：

1. 风格库（已完成）。
2. 提示词模板（已完成）。
3. 素材 AI 辅助（已完成）。
4. 全文润色、多版本改写和恢复润色前正文（已完成）。
5. 归档筛选（已完成）。
6. 导入导出（待做）。

完成后，原生端成为唯一推荐使用入口。

### 阶段 C：智能写作教练升级

状态：核心智能链路已完成，长期训练系统继续演进。

目标：

1. 复盘趋势（已完成当前版本）。
2. 常见问题统计（已完成当前版本）。
3. 修改前后版本差异对比（已完成）。
4. 智能下一步的上下文观察、执行计划、风险提示（已完成）。
5. 代理式初稿和质量门（已完成）。
6. 按诊断改全文（已完成）。
7. 训练计划（后续待做）。
8. 风格记忆更新（后续待做）。
9. 写作能力标签（后续待做）。

产品从“写作工作台”升级为“写作训练系统”。

### 阶段 D：桌面产品化

目标：

1. 应用图标。
2. 设置窗口完善。
3. 打包分发。
4. 签名和公证。
5. 自动更新方案。
6. 数据备份和恢复。



## 15. 风险与决策



### 15.1 风险


| 风险                          | 影响     | 应对                                             |
| --------------------------- | ------ | ---------------------------------------------- |
| AI 返回 JSON 不稳定              | 解析失败   | 保留 raw_output，加入 schema 修复                     |
| Prompt 分散                   | 后续难维护  | 已引入 SQLite `prompt_templates` 和 `ContextPackage` |
| 旧版能力迁移遗漏                    | 使用困惑   | 以 PRD 和 XCTest 作为原生端验收依据                       |
| 本地数据库迁移复杂                   | 用户数据风险 | 保留迁移测试和备份机制                                    |
| 写作教练过度打分                    | 用户焦虑   | 强调修改顺序和训练重点，弱化排名感                              |
| SwiftUI TextEditor 局部选区能力有限 | 局部改写困难 | 已引入 AppKit `NSTextView` bridge，后续关注选区和 undo 行为 |
| 代理链路步骤变多                    | 单次生成等待变长 | 展示运行轨迹、质量门和 fallback，让等待换来可审查的中间判断                |




### 15.2 已确认决策

1. macOS 原生端是主线。
2. FastAPI/Next/Web 兼容路径已清理。
3. API Key 使用 Keychain。
4. 数据默认本地 SQLite。
5. 新 AI 能力优先做结构化输出。
6. 直接初稿已升级为代理式初稿，后续不再恢复“一次请求直出全文”的主链路。
7. 写作教练和智能下一步是长期核心差异点。



## 16. 附录：当前关键文件


| 文件                                                                                             | 说明               |
| ---------------------------------------------------------------------------------------------- | ---------------- |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/App/CreativeWorkshopMacApp.swift`       | 原生 App 入口        |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/ContentView.swift`                | 主窗口三栏结构          |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/ComposerView.swift`               | 写作画布             |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/InspectorView.swift`              | 运行上下文、写作教练、统计、选题 |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/MaterialsView.swift`              | 素材箱              |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/SidebarView.swift`                | 侧边栏              |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Views/SettingsView.swift`               | 模型设置             |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Stores/WorkshopStore.swift`             | 原生状态和工作流编排       |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Models/WorkshopModels.swift`            | 数据模型             |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/NativeDatabase.swift`          | 原生 SQLite 数据层    |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/NativeAIClient.swift`          | 原生 AI API 客户端    |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/AIWorkflowRunner.swift`        | AI 调用、JSON 清洗、fallback 和调用记录统一执行器 |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/WritingContextBuilder.swift`   | 智能写作上下文包         |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/NativePrompts.swift`           | 原生 Prompt        |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/NativeFallbacks.swift`         | 本地 fallback      |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Services/KeychainCredentialStore.swift` | API Key 存储       |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Support/AgentDraftQualityGate.swift`    | 代理式初稿质量门         |
| `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Support/SelectedTextEditor.swift`       | 正文选区编辑桥接         |
| `script/build_and_run.sh`                                                                      | 原生 App 构建和启动     |
| `ARCHITECTURE.md`                                                                              | 架构边界             |




## 17. 附录：推荐下一步任务拆分



### 17.1 近期最值得做

状态：当前待办。

1. 导入导出：JSON 导入导出、Markdown 导出。
2. 流式输出：让长文本生成过程可见、可取消。
3. 模型路由：按任务选择 DeepSeek、OpenAI-compatible、本地模型或 Claude 兼容代理。
4. 自动保存：降低长文编辑和待复核过程中的丢失风险。
5. 打包产品化：图标、签名、公证、自动更新预案。



### 17.2 技术债清理

状态：已完成。

1. 抽象 `ContextPackage`。
2. 抽象 `AIWorkflowRunner`。
3. 把 Prompt 从静态函数升级为可编辑模板。
4. 扩展 `ai_calls` 记录输入输出摘要。
5. 增加数据库迁移版本号。



### 17.3 可暂缓

1. 云同步。
2. 多用户。
3. 微信公众号自动发布。
4. 移动端。
5. 浏览器插件。
6. 外部热点抓取。



## 18. AI 写作质量改造提案（文学写作方向，已实施）

状态：**已实施**（2026-07-01）。18.3（P1）、18.4（P2）全部落地；18.5（P3）中"选题去重"已落地，"分段生成"已被代理式初稿链路吸收为分段成稿，流式输出已于后续第 22 章任务 9 落地（见 19.3.5 实施记录）。本章原为提案，现按实施结果回填状态，具体范围裁剪和实现方式差异见各节末尾的"实施记录"、18.11 和 18.12 总结；第 5、8、9、10、13 章已按本章结论同步更新。

本章范围限定在"智能写作"相关能力：写作教练（诊断）、代理式初稿、大纲/成稿、全文润色、局部改写、风格与素材上下文。不涉及打包签名、多用户、云同步等第 14 章阶段 D 范围。实施过程中同样没有触碰这些范围之外的部分。

依据说明：以下问题和结论来自对本机真实使用数据的核对，包括 `~/Library/Application Support/CreativeWorkshopMac/creative_workshop.sqlite3` 中的 `articles`、`writing_reviews`、`topics`、`ai_calls` 历史记录，以及 `exports/` 下的早期草稿文件，时间范围集中在 2026-06-25 至 2026-06-30。样本量小（单用户、几十次调用），结论作为方向参考，不作为统计意义上的定论。

本章使用的 P1/P2/P3 是"AI 写作质量改造"内部的优先级，用于本提案自身排期，不等同于第 13 章整体验收的 P0/P1/P2 分级。对应关系：本章 P1 建议归入第 14 章"阶段 B：补齐高频 P1 能力"范围一并执行；本章 P2 建议归入"阶段 C：智能写作教练升级"；本章 P3 对应"可暂缓"。

#### 18.0 实施情况总览

| 章节 | 内容 | 状态 |
| --- | --- | --- |
| 18.3.1 | 诊断-改写闭环 | 已实施 |
| 18.3.2 | 诊断记忆与防空转 | 已实施 |
| 18.3.3 | 文学性诊断维度与作者雷区清单 | 已实施 |
| 18.3.4 | 体裁化风格与评价标准 | 已实施 |
| 18.3.5 | 生成后轻量自检信号 | 已实施 |
| 18.4.1 | 人工复核工作流产品化（"待复核"态） | 已实施 |
| 18.4.2 | 文学写作能力雷达 | 已实施 |
| 18.4.3 | 读者视角模拟 | 已实施 |
| 18.5.1 | 分段生成 + 段落级连贯性校验 | 已部分实施（代理式初稿内置分段成稿；流式逐段输出暂缓，理由见 18.11） |
| 18.5.2 | 选题/素材生成去重 | 已实施 |
| 18.12 | Claude Code / Codex 式代理写作升级 | 已实施 |

涉及的 Swift 源码改动集中在：`WorkshopModels.swift`、`NativeDatabase.swift`（schema version 5）、`WritingContextBuilder.swift`、`NativePrompts.swift`、`NativeFallbacks.swift`、`NativeAIClient.swift`、`AIWorkflowRunner.swift`、`WorkshopStore.swift`、`SelectedTextEditor.swift`、`StringExtensions.swift`，新增 `WritingDimensionAnalytics.swift`、`TopicDeduplicator.swift`、`AgentDraftQualityGate.swift`；UI 改动集中在 `SettingsView.swift`、`InspectorView.swift`、`ComposerView.swift`。改造后 `swift build`/`swift test` 全量通过（25 个单元测试，含按新增字段更新后的 `NativeDatabaseTests` 和代理质量门测试）。

### 18.1 背景：基于真实使用数据的诊断

1. 写作教练已经具备真实的文学判断力，但表现不稳定。文章《时间扑面而来，我们都在葬花》（古典文本再解读方向）先后被诊断 4 次。前两次（2026-06-30 15:52、15:59）诊断内容还停留在"正文缺失、大纲清晰"这类表层判断；后两次（16:07、16:15）在正文写完后，诊断准确指出"开头以'我'建立个人代入感，但引入《葬花吟》后'我'几乎消失，文章变成客观作品赏析""'带着勇气的凝望''并肩的陪伴'等表述接近心灵鸡汤的总结句式，削弱了作者追求的'真诚、克制'风格""对经典的解读缺乏作者独特的二次提炼，显得面熟"，甚至挑出了"葬花呤"的错字。这些判断已经是合格文学编辑的水准，说明底层模型能力足够；问题是这种水准目前完全取决于喂给模型多少真实正文和运气，产品没有把评价标准显性建模，质量忽高忽低。
2. 诊断到修改的闭环效率低。同一篇文章 4 次诊断，`overall_score` 是 72、72、72、75，几乎没有变化。诊断给出的 `revision_plan` 很具体（例如"在每个分段解读后嵌入一句个人式回扣，保持'我'的线索"），但产品里没有把这些建议变成可以直接执行的动作，作者只能对照 Inspector 里的文字，手动回到正文里找位置、手动改。
3. 无变化也会重复诊断，缺少防空转机制。文章《如何写红楼梦的林黛玉？》在正文为空的情况下，9 秒内被连续触发 6 次写作诊断（14:39:11-14:39:20），返回的都是同一句"当前更像一个写作准备稿，下一步应先完成可修改的正文"。这批调用发生在尚未配置 API Key 时，本身不构成模型调用问题，但也说明产品没有识别"内容自上次诊断后未变化"的能力，真实调用场景下会白白消耗等待时间和 token。
4. 诊断维度覆盖了文学性问题，但依赖模型自由发挥，产品未显性建模。当前 `WritingReviewIssue.dimension` 的取值范围是"开头/结构/观点/素材/表达/节奏/风格"，通用于公众号说理文，不特指文学写作；上一条提到的"人称视角脱落""文艺腔滑向鸡汤腔""引用经典缺乏个人二次提炼"这些真正命中问题的判断，都是模型在通用维度框架下自由发挥出来的，诊断一次就随 Inspector 关闭而消失，没有沉淀为可复用的评价标准或"这位作者的雷区"。
5. 长文本一次性生成在早期草稿中出现过明显的连贯性劣化。`exports/1-MCP 是什么_我试着用最笨的方式讲清楚.md` 是一篇未经写作诊断的早期草稿：开头两段场景清晰、语气自然，但从中段开始出现明显的语句破碎、逻辑跳跃、比喻堆叠不清的情况（例如"这边用的差别主要在MCP专门只作为其中打通那个环节提供高德map搜索词参考组和秒级整理响应给你用一句话总结了此时附近有什么等级的路线"）。这提示"一次性长输出"存在从清晰滑向混乱的真实风险，仅靠事后诊断发现问题不够及时，生成阶段就需要自查。
6. 选题生成缺少去重。选题池中"自由自在如何定义"方向的 3 个选题被完整生成了两遍（`我重新看待…之后，发现它并不遥远` 等标题一字不差各出现 2 次）。这是次要发现，附带记录在本次提案的 P3 里。
7. 真实写作方向已经跨越至少三种体裁，但风格系统只有一份通用配置。数据库里同时存在"情感文学"（成都系列）、"文学"（《葬花吟》/红楼梦系列）、"小红书文案" 三种方向，而 `style_profiles` 里目前只有一条"默认公众号风格"，所有方向共用同一套语言/语气/结构描述和评价尺子。



### 18.2 改造目标与原则

1. AI 不做最终判断，只降低人工判断的成本。作者会人工检查产出质量，产品的责任是让这次检查更快、更准、更有依据，而不是让检查这件事显得可以被跳过。每一项改造都先问这个问题。
2. 文学质量优先于生成速度。对文学写作方向，"具体、真实、克制"优先于"流畅、快、多"，涉及取舍时向前者倾斜。
3. 让模型的判断力变成产品资产，不是一次性烟花。诊断中被模型准确抓住的问题，应该有机会沉淀为可追溯、可复用的"作者雷区"，而不是关掉 Inspector 就消失，下次同样的问题还要模型重新发现一次。
4. 一个体裁一套标准。情感文学随笔、经典文本再解读、短平快文案不应该共用同一套"开头/结构/观点/素材/表达/节奏/风格"通用尺子。
5. 长输出必须自证，不能只靠事后诊断。把"发现问题"尽量提前到生成完成的那一刻，让人工检查从"通读找茬"变成"核对提示"。



### 18.3 P1 改造清单（近期）



#### 18.3.1 诊断-改写闭环

改造前现状：`writing_reviews.issues[].suggestion` 只能读，不能点；作者要自己在正文里找到 `excerpt` 对应的位置，再手动触发局部改写。

改造方向：

1. `WritingReviewIssue` 增加稳定的 `id` 字段。
2. 局部改写增加"自定义改写指令"路径：在现有 6 个 `RewriteMode`（自然、扩写、缩短、加深、画面感、口语化）之外，允许直接传入一句自然语言目标，不强制落在预设 mode 上。
3. Inspector 里每条 issue 增加"定位并改写"按钮：按 `excerpt` 在正文中定位并选中对应片段（复用 `SelectedTextEditor` 的选区能力），调用局部改写时把这条 issue 的 `suggestion` 作为改写指令。
4. 改写结果仍然是"生成候选 → 人工确认后替换"，不自动落地，人工检查环节保留。

涉及模块：`WorkshopModels.swift`（`WritingReviewIssue` 加 `id`，`RewriteMode`/`rewriteSelection` 支持自由指令）、`NativePrompts.swift`（`rewriteSelection` 支持自由 instruction）、`SelectedTextEditor.swift`（按 `excerpt` 定位选区）、`InspectorView.swift`（按钮与交互）、`WorkshopStore.swift`（新增 `rewriteFromIssue(_:)`）。

验收标准：

1. 每条诊断 issue 若能在当前正文中定位到 `excerpt`，Inspector 必须展示可点击的改写入口。
2. 点击后必须先选中对应正文片段，再调用改写，不允许改写超出该片段范围。
3. 改写候选生成后必须经过一次人工确认才写入正文，确认前可以放弃。
4. 定位失败（正文已改动、`excerpt` 不再匹配）时必须提示"未找到对应片段"，不得静默改写错误位置。

**实施记录**：按方向 1-4 全部落地。`RewriteMode` 新增 `.custom` case（不出现在工具栏「局部改写」菜单里，只由诊断入口触发），`rewriteSelection` 支持 `customInstruction` 参数直接传入 `issue.suggestion`。`WorkshopStore.canLocateIssue(_:)`/`rewriteFromIssue(_:)` 用 `content.range(of:)` 精确匹配 `excerpt`（找不到即返回 nil/提示，不做近似匹配），命中后设置 `contentSelection` 并滚动可见（`SelectedTextEditor.scrollRangeToVisible`）。生成结果先存入 `PendingIssueRewrite`，Inspector 的"定点改写候选"卡片提供"确认替换正文"/"放弃"两个按钮，确认前 `replaceSelectedContent` 会比对原文是否与定位时一致，正文已变化则拒绝写入并提示重新定位。

#### 18.3.2 诊断记忆与防空转

改造前现状：`writingReview` 不读取该文章历史诊断，每次都是从零评估；也不检测正文是否变化，重复点击会重复调用模型或本地兜底。

改造方向：

1. 在 `WritingContextBuilder` 或直接在 `NativePrompts.writingReview` 中，注入该文章最近一次诊断的 `issues` 摘要和 `revision_plan`。
2. Prompt 增加要求："先判断上一次诊断提出的问题是否已经解决，只重点分析仍未解决和新出现的问题"。
3. `WritingReviewResult` 增加可选字段 `resolved_from_last`（本次判定已解决的历史问题列表），在 Inspector 中与本次新问题分开展示。
4. 触发诊断前做一次变化检测：若标题/摘要/正文/大纲/想法自上次诊断以来没有实质变化，弹出确认提示（"内容与上次诊断时相同，仍要重新诊断吗？"），而不是直接调用模型。

涉及模块：`WritingContextBuilder.swift`、`NativePrompts.swift`、`WorkshopModels.swift`、`WorkshopStore.swift`（`reviewCurrentDraft` 加变化检测）、`NativeDatabase.swift`（按 `article_id` 取最近一条历史 review）。

验收标准：

1. 文章存在历史诊断时，本次诊断的模型请求中必须包含上一次的问题摘要。
2. 诊断结果中必须能看到"已解决"和"仍未解决/新增"问题的区分，即便"已解决"列表为空也要有明确展示。
3. 内容自上次诊断后未变化时，必须先提示后才允许发起新的模型调用。

**实施记录**：`NativePrompts.writingReview` 新增 `previousReview` 参数，注入上一次诊断的问题摘要和修改顺序（`previousReviewBlock`），并要求模型输出 `resolved_from_last`。`WritingReview`/`WritingReviewResult` 增加 `resolved_from_last: [String]` 和 `reviewed_snapshot: String?`（可复核文本快照，用于变化检测，比对标题/摘要/正文/大纲/想法拼接后的整体快照）。`WorkshopStore.reviewCurrentDraft()` 在调用模型前比较当前快照与文章最近一条历史诊断的 `reviewed_snapshot`，相同则不调用模型，置位 `showUnchangedReviewPrompt = true`；`ComposerView` 用 `.confirmationDialog` 承载"仍要诊断/取消"，比原方案设想的 Inspector 内嵌提示更贴近触发点、不受右侧栏是否可见影响。Inspector 复盘卡片新增"已解决（较上次诊断）"展示行，空列表时也会显示"暂无已判定解决的历史问题"而不是留白。

#### 18.3.3 文学性诊断维度与作者雷区清单

改造前现状：`dimension` 取值通用（开头/结构/观点/素材/表达/节奏/风格），文学性问题（人称视角、文艺腔/鸡汤腔、意象与细节）能不能被指出，取决于模型当次发挥。

改造方向：

1. 在 `writingReview` prompt 中为 `dimension` 提供更细的文学向候选说明，供模型优先选用：人称视角、意象与细节、留白与节奏、情感真实度、文本引用关系（经典/素材引用是否服务于个人表达）、语言腔调（含文艺腔/鸡汤腔/营销腔判定）。保留原有 7 个通用维度作为兜底，不做强制枚举校验，避免模型输出被打回。
2. 新增"作者雷区清单"：`style_profiles` 增加 `known_pitfalls` 字段（JSON 数组，每项含描述、来源 `review_id`、确认状态），或拆成独立表（见 18.6）。
3. 新增"从复盘归纳雷区"动作：扫描最近 N 条 `writing_reviews.issues`，按 `problem` 语义聚类出高频问题，生成候选雷区，作者手动勾选确认后才写入清单——归纳可以自动，写入必须人工确认。
4. 写作诊断和四类生成 prompt（代理式初稿、大纲成稿、全文润色、局部改写）都注入 `known_pitfalls`，明确要求"重点检查是否再次出现清单中的问题"。

涉及模块：`WorkshopModels.swift`、`NativeDatabase.swift`（新字段/新表 + CRUD）、`NativePrompts.swift`（`styleDescription` 或新函数注入雷区清单）、风格库编辑 UI（与 3.4 节原列的风格库编辑能力合并实现）。

验收标准：

1. 写作诊断输出的 `dimension` 允许但不强制使用新增文学向取值。
2. 风格库界面可以查看、编辑、删除雷区清单条目，且每条能追溯到来源诊断记录。
3. 雷区清单非空时，写作诊断和至少一种生成流程的 prompt 中必须包含该清单内容（可通过检查请求文本或 `ai_calls` 记录验证）。
4. 雷区归纳结果在作者确认前不得直接写入正式清单。

**实施记录**：按 18.6 表格的方案落地，`known_pitfalls` 作为 `style_profiles` 的 JSON 字段（未拆独立表，见下方范围裁剪说明），元素类型 `AuthorPitfall{ description, source_review_id?, created_at? }`。`writingReview` prompt 补充了文学向 `dimension` 候选说明（人称视角/意象与细节/留白与节奏/情感真实度/文本引用关系/语言腔调），不做枚举校验。新增 `summarizePitfalls` 工作流：`WorkshopStore.summarizeAuthorPitfalls()` 汇总该风格档案的历史诊断 issue（现状取全部历史，见范围裁剪说明），调用模型聚类出 `PitfallCandidate` 候选，落在 `pitfallCandidates`（`@Published`），Settings 里"作者雷区清单"区域分别列出已确认条目（可删除）和待确认候选（可"确认加入"/"忽略"），候选不经确认不会写入 `style_profiles.known_pitfalls`。`known_pitfalls` 已通过 `styleDescription`/`commonVariables` 注入写作诊断和全部生成类 prompt。

**范围裁剪**：`allIssuesHistory()` 目前取全部历史诊断问题，未按 `genre` 过滤（`writing_reviews` 表本身不记录体裁，需要联查文章表才能做体裁级过滤，与本次改造的其余部分相比价值不高，暂不做）；未拆分独立的 `author_pitfalls` 表，理由和权衡见 18.11。



#### 18.3.4 体裁化风格与评价标准

改造前现状：`style_profiles` 只有一条"默认公众号风格"，情感文学随笔、经典文本再解读、小红书文案共用同一套描述；few-shot 样本固定取 `sample_texts` 的前 3 篇，与体裁、话题是否相关无关；样本需要作者手动粘贴维护，和不断积累的 `articles` 历史文章是脱节的。

改造方向：

1. `StyleProfile` 增加 `genre` 字段（如：情感文学随笔、经典文本再解读、轻科普、短平快文案，作者可自定义新增），可与 `Topic.direction` 对应或独立选择。
2. 每个 `genre` 关联一段"评价重点"补充文本（例如经典文本再解读强调"是否保留第一人称、是否滑向说教"；情感文学随笔强调"细节是否具体、情绪是否悬浮"），拼入 `writingReview` 和生成类 prompt。
3. 选题、大纲、初稿生成时按 `direction` 优先匹配对应 `genre` 的风格档案，不再固定使用 `is_default` 风格。
4. Few-shot 样本来源从"固定取 `sample_texts` 前 3 篇"，扩展为"优先从最近同 `genre` 的已完成/已发布 `articles` 中抽取"，减少手动维护成本，让风格样本随创作积累自动更新；`sample_texts` 保留作为人工指定样本的补充/兜底。

涉及模块：`WorkshopModels.swift`、`NativeDatabase.swift`（迁移 + CRUD）、`NativePrompts.swift`（`styleDescription`/`samplesBlock` 按 `genre` 取材）、风格库编辑 UI。

验收标准：

1. 至少支持两个体裁并存，且可以独立编辑各自的评价重点文本。
2. 同一篇正文，用两种不同体裁的评价重点跑写作诊断，输出内容应有可观察差异（人工抽检确认，不要求自动化断言）。
3. 存在同体裁历史文章时，生成类工作流的 few-shot 样本必须优先包含该体裁文章，而不是永远固定前 3 篇 `sample_texts`。

**实施记录**：`StyleProfile` 新增 `genre`/`genre_focus`，Settings 风格库表单新增对应输入框（体裁标签 + 体裁评价重点多行文本）。`NativeDatabase.styleProfile(forDirection:)` 按 `genre` 精确匹配风格档案，未命中则回退默认风格。`WorkshopStore.resolveStyle()` 是新增的统一入口：先按当前写作方向取体裁化风格，再调用 `recentArticlesForSamples(genre:excludingArticleID:limit:)` 取最近 3 篇同体裁、非空正文的文章，拼接在 `style.sample_texts` 前面（人工样本作为补充留在后面），`WorkshopStore` 里所有原先读 `database.defaultStyle()` 的工作流（选题、大纲、初稿、成稿、润色、局部改写、定点改写、写作诊断、智能下一步、发布物料、读者视角模拟）已统一改为调用 `resolveStyle()`，代码中已不存在直接调用 `database.defaultStyle()` 的地方。`genre`/`genre_focus` 也通过 `commonVariables`/`styleDescription` 注入 prompt。`Article`/`ArticleSaveRequest` 增加 `genre`，保存文章时落盘当前写作方向，`openArticle` 反向恢复。

#### 18.3.5 生成后轻量自检信号

改造前现状：旧版初稿、大纲成稿、全文润色生成结果后直接展示给作者，没有任何自我检查，长文本"从清晰滑向混乱"的风险（见 18.1 第 5 条）完全依赖作者从头读一遍才能发现。

改造方向：

1. 在 `quickDraft`、`draftFromOutline`、`polishDraft` 成功拿到结果后，自动追加一次轻量结构化自检调用（新增工作流 `draftSelfCheck`），只关注少量高风险信号：是否偏离大纲/想法、结尾是否落入套话或口号、是否存在明显语句不连贯或重复、字数是否与预期明显不符。
2. 返回不超过 3 条 `flagged_excerpts`（`excerpt` + `concern`），在编辑器里以高亮或旁注形式提示"建议复查"，不弹窗打断、不阻塞主流程。
3. 自检调用失败或模型不可用时静默跳过，不影响主流程，也不清空已生成内容，遵守第 12 章"AI 失败时不清空用户已有内容"的既有非功能要求。

涉及模块：`NativePrompts.swift`（新增 `draftSelfCheck`）、`WorkshopModels.swift`（新增 `DraftSelfCheckResult`）、`NativeAIClient.swift`（新增方法）、`WorkshopStore.swift`（在三个生成动作后串接调用）、`ComposerView.swift`（高亮/旁注展示）。

验收标准：

1. 三类生成动作成功后，若自检调用也成功，编辑器必须能展示 0～3 条复查提示。
2. 自检调用失败时，主生成结果的展示和保存不受影响。
3. 自检不修改正文内容，只做提示。

**实施记录**：新增 `draftSelfCheck` 工作流（`NativePrompts`/`NativeAIClient`/`NativeFallbacks`/`AIWorkflowRunner` 均已支持，解析失败时兜底返回空结果而不是抛错）。三个生成动作统一收口到新增的 `WorkshopStore.finalizeGeneratedDraft(...)`，生成成功后立即串一次 `draftSelfCheck` 调用，结果存入 `latestSelfCheck`。展示形式比"高亮或旁注"二选一更完整：`SelectedTextEditor` 新增 `highlightExcerpts` 参数，用 `NSLayoutManager` 的临时属性（`addTemporaryAttribute(.backgroundColor:...)`）给命中的原文片段加背景高亮，不改变 `NSTextStorage`/不影响撤销栈；`ComposerView` 同时在编辑器上方加了一条"自检建议复查 N 处"的旁注条，逐条列出 `excerpt` + `concern`，附"知道了"按钮可随时清除。自检失败时静默跳过、不影响主生成结果，符合第 12 章既有要求。



### 18.4 P2 改造清单（中期）



#### 18.4.1 人工复核工作流产品化（"待复核"态）

改造前现状：旧版初稿、大纲成稿、全文润色直接写入 `title`/`content`/`summary`，"人工检查"是一个隐性动作，没有对应的界面承载；`draft_versions` 已经记录改前改后快照，但没有"是否已经过人工确认"的状态位。

改造方向：

1. `draft_versions` 增加 `review_status` 字段（`pending`/`confirmed`），历史记录默认视为 `confirmed`。
2. 大范围生成动作（代理式初稿、大纲成稿、全文润色）产出的版本先落地为 `pending`，Inspector 新增"复核"视图：并排展示改前内容、本次生成内容、18.3.5 的自检提示、命中的作者雷区清单条目。
3. 作者点击"确认定稿"才把内容标记为 `confirmed` 并作为文章当前正文；点击"放弃"则回退到改前版本。局部改写维持现状（默认直接应用、可恢复），因为改动范围小、复核成本本身就低，不需要额外流程。

涉及模块：`NativeDatabase.swift`（`draft_versions` 加字段）、`WorkshopModels.swift`、`WorkshopStore.swift`、`InspectorView.swift`/`ComposerView.swift`（复核视图）。

**实施记录**：`draft_versions` 增加 `review_status`（默认 `confirmed`，历史记录不受影响），新增 `confirmDraftVersion(id:)`/`deleteDraftVersion(id:)`。三个大范围生成动作统一走 `finalizeGeneratedDraft(...)`：正文立即更新到编辑器供预览（保留原有"生成即可见"的体验），同时把这次改动存成 `pending` 版本，并把 `PendingDraftReview{ draftVersionID, before, after, selfCheck, matchedPitfalls, usedFallback }` 写进 `pendingDraftReview`。确认/放弃入口给了两处：Inspector 复核 tab 顶部的 `PendingDraftReviewCard`（改前/改后差异对比复用现有 `TextDiff` 工具、自检提示、命中的雷区清单）和 `ComposerView` 编辑器上方一条不依赖右侧栏的确认条（同样是"确认定稿"/"放弃"），因为右侧栏可能被隐藏或切换到其他 tab。"确认定稿"把 `draft_versions` 行翻成 `confirmed`；"放弃"删除该行并把正文回退到生成前快照。`saveArticle()` 增加前置校验：存在未处理的 `pendingDraftReview` 时拒绝保存并提示"还有未确认的生成结果"。切换文章/新建草稿时，若还有未处理的待复核记录，视为隐式放弃并清理数据库里的孤儿 `pending` 行（不恢复正文，因为正文即将被新文章/新草稿覆盖）。局部改写维持原有直接应用/`draft_versions` 默认 `confirmed` 的行为，未受影响。

#### 18.4.2 文学写作能力雷达（复盘深化）

改造前现状：`training_focus` 是自由文本列表，当时还没有第 8.9 节"复盘洞察"目标能力里提到的"跨文章统计作者弱项"，也没有专门针对文学维度的统计。

改造方向：基于 18.3.3 扩展后的文学向 `dimension`（人称视角、意象与细节、留白与节奏、情感真实度、语言腔调等），统计最近 N 篇文章每个维度出现的频次和严重度趋势，在复盘页面用雷达图或趋势线展示，帮助作者看到"哪类问题在减少、哪类在反复出现"。

涉及模块：`NativeDatabase.swift`（统计查询）、复盘相关视图（现有 Inspector 复盘区或独立页面）。

**实施记录**：统计逻辑做成独立的纯函数模块 `WritingDimensionAnalytics.swift`（`trends(from:sampleSize:)`），不依赖数据库查询，直接对内存里的 `WorkshopStore.writingReviews`（已按时间倒序）按最近样本的前/后半段统计每个 `dimension` 的出现频次，得到 `improving`/`steady`/`worsening` 三态趋势，方便单独测试。展示形式用简单条形对比而非 Swift Charts 雷达图/趋势线——项目部署目标是 macOS 13，引入 Charts 本身没有障碍，只是当前样本量小（单用户几十条诊断）时条形对比已经足够表达"同一维度前后半段频次变化"，暂不需要更重的图表方案；后续样本量上升、需要同时对比多维度时，再引入 Charts 替换成雷达图会是更值得做的升级。落在 Inspector 复盘 tab 新增的 `DimensionTrendsCard`。

#### 18.4.3 读者视角模拟

改造前现状：现有诊断只有"编辑视角"（问题 + 建议），缺少"读者视角"（真实阅读体验中的兴趣变化）。

改造方向：新增一种可选的补充诊断视角，模拟 1～2 种典型读者，预测"最可能在哪一段失去兴趣""哪一句最可能被记住或转发"，作为定性提示，不计入 `overall_score`，不替代现有编辑视角诊断。

涉及模块：`NativePrompts.swift`（新增 prompt）、`WorkshopModels.swift`（新增结构）、Inspector 新增展示区。

**实施记录**：新增 `readerPerspective` 工作流（prompt/`ReaderPerspectiveResult{ reader_persona, drop_off_point, most_memorable_point, note }`/`NativeAIClient`/`NativeFallbacks`），只在正文非空时可用（`canRunReaderPerspective`）。结果落在 `latestReaderPerspective`，独立展示在 Inspector 复盘 tab 的 `ReaderPerspectiveCard`（画像/最可能失去兴趣的位置/最可能被记住的一句/备注），需要作者手动点击"模拟"触发，不随写作诊断自动运行，不写入 `overall_score`，不影响现有编辑视角诊断结果。

### 18.5 P3 改造清单（已裁剪落地/探索）

1. 分段生成 + 段落级连贯性校验：原提案设想把"一次性长 JSON 输出"改为"大纲分段 → 逐段生成 → 段落衔接校验"。当前已经裁剪落地为代理式初稿中的 `sectionDraft`：先由 `writingBrief` 和 `argumentCheck` 建立写作计划，再分段生成正文，并通过 `draftCritique` 与 `draftSelfCheck` 提供连贯性复查线索。真正的流式逐段输出和单段重跑仍暂缓，理由见 18.11。
2. 选题/素材生成去重：生成新选题前，对候选标题与近期已有选题做相似度比较，提示或过滤重复项（对应 18.1 第 6 条发现的真实重复案例）。**已实施**：新增 `TopicDeduplicator.swift`（bigram Jaccard 相似度，默认阈值 0.6），`generateTopics`/`generateTopicsFromIdea` 在写入数据库前先用现有 `topics` 过滤候选，重复项不入库；Inspector 选题列表在有过滤发生时显示"本次有 N 个候选选题与已有选题重复，已自动过滤"，可展开看具体标题；`statusText` 同步给出"已生成 X 个（另有 Y 个重复已过滤）"的反馈。



### 18.6 数据模型变更汇总


| 表 / 字段                               | 变更                                      | 用途                  |
| ------------------------------------ | --------------------------------------- | ------------------- |
| `writing_reviews.issues` 内的 issue 对象 | 增加 `id`                                 | 支持诊断-改写闭环中的定点定位     |
| `writing_reviews`                    | 增加 `resolved_from_last`（JSON 数组）        | 记录本次判定已解决的历史问题      |
| `writing_reviews`                    | 增加 `reviewed_snapshot`（TEXT）             | 诊断防空转的变化检测快照（18.3.2，原方案未列，实施时补充） |
| `style_profiles`                     | 增加 `genre`（TEXT）                        | 体裁标签，驱动差异化评价重点和样本匹配 |
| `style_profiles`                     | 增加 `genre_focus`（TEXT）                   | 体裁评价重点文本（18.3.4，原方案未列，实施时补充） |
| `style_profiles`                     | 增加 `known_pitfalls`（JSON，若不拆表则用此字段）     | 作者雷区清单              |
| `articles`                           | 增加 `genre`（TEXT）                        | 保存文章时记录写作方向，供体裁化 few-shot 样本匹配（18.3.4，原方案未列，实施时补充） |
| `draft_versions`                     | 增加 `review_status`（TEXT，默认 `confirmed`） | 支持"待复核"工作流          |
| `writing_advisor_runs`               | 增加 `context_findings`、`execution_plan`、`risk_notes` | 支持 Claude Code / Codex 式智能下一步 |

**实施记录**：以上字段全部落地，`NativeDatabase.ensureColumns()` 迁移覆盖，`nativeDatabaseSchemaVersion` 由 3 升到 5，新老数据库均可正常升级（`swift test` 中 `NativeDatabaseTests` 已覆盖新字段的读写）。

雷区清单**未**拆分为独立的 `author_pitfalls` 表，维持塞进 `style_profiles.known_pitfalls`（JSON 数组）的方案，权衡说明见 18.11。

```sql
-- 未采用的备选方案，保留在此供后续需要独立管理/跨风格档案追溯雷区时参考
author_pitfalls
id                INTEGER PRIMARY KEY
style_profile_id  INTEGER
description       TEXT NOT NULL
source_review_id  INTEGER
confirmed         INTEGER DEFAULT 0
created_at        TEXT
updated_at        TEXT
```



### 18.7 AI 系统设计变更汇总

1. `NativePrompts.swift` 新增：`writingBrief`、`argumentCheck`、`sectionDraft`、`draftCritique`、`improveDraftFromReview`、`draftSelfCheck`（18.3.5）、读者视角模拟 prompt（18.4.3，P2）；`rewriteSelection` 增加自由 instruction 支持（18.3.1）；`writingReview` 注入历史诊断摘要与作者雷区清单（18.3.2、18.3.3）；`writingAdvisor` 增加上下文观察、执行计划和风险提示。
2. `WritingContextBuilder` 增加字段：`last_review_summary`、`known_pitfalls`、`genre`，供多个 prompt 复用。
3. `NativeAIClient.agentDraft(...)` 将初稿生成拆成 brief、论点检查、分段成稿和成稿自评四个结构化步骤。
4. 第 9.3 节规划的 `ContextPackage` 抽象已经在本次改造中落地：`known_pitfalls`、`genre`、`last_review_summary` 统一进入上下文包，再由多个工作流复用。

**实施记录**：1、2、3 按计划落地。4 已完成第 17.2 节意义上的技术债清理：`WritingContextPackage` 改为 `ContextPackage` 的 `typealias`，`WritingContextBuilder.build(...)` 统一返回 `ContextPackage` 并填充新增字段；`AIWorkflowRunner` 统一承接 URLSession 调用、JSON 清洗解析、fallback、耗时统计和输入输出摘要；Prompt 已升级为数据库可编辑模板；`ai_calls` 已记录 `input_summary`/`output_summary`；数据库 `user_version` 已由 schema version 管理。



### 18.8 验收标准（AI 写作质量改造）

1. 每条写作诊断 issue 若能定位到正文原文，都能一键发起针对性改写，改写结果需人工确认才替换正文。**已满足**：`canLocateIssue`/`rewriteFromIssue`/`PendingIssueRewrite` 确认流程。
2. 同一篇文章连续两次诊断之间，若标题/摘要/正文/大纲/想法未变化，必须先提示后才允许重新调用模型。**已满足**：`reviewCurrentDraft()` 变化检测 + `ComposerView` 确认弹窗。
3. 文章存在历史诊断时，写作诊断的模型请求必须包含上一次的问题摘要，输出必须区分"已解决"和"仍未解决/新增"的问题。**已满足**：`previousReviewBlock` 注入 + `resolved_from_last` 输出。
4. 至少支持两种体裁（如"情感文学随笔"和"经典文本再解读"）的独立评价重点，且相同正文在两种体裁下的诊断输出应有可观察差异。**结构上已满足**（`genre`/`genre_focus` 可独立编辑、按体裁匹配风格档案并注入 prompt）；"输出应有可观察差异"这一条要求真实调用两种体裁跑同一篇正文人工比对，属于运行期验证，不是本次代码交付能自证的部分，需要作者实际使用后确认。
5. 代理式初稿、大纲成稿、全文润色成功后，若自检调用也成功，编辑器必须展示 0～3 条复查提示，且不阻塞主流程、不修改正文。**已满足**：`draftSelfCheck` + 编辑器高亮/旁注条，失败静默跳过。
6. 代理式初稿、大纲成稿、全文润色的产出默认进入"待复核"状态，未经作者确认不得覆盖文章已保存的定稿内容；局部改写维持现状不受影响。**已满足**：`pendingDraftReview` + `saveArticle()` 前置校验。
7. 风格库支持查看、编辑作者雷区清单，且每条可追溯到来源诊断记录；雷区归纳结果在作者确认前不得自动生效。**已满足**：Settings 雷区清单 UI + `source_review_id` 追溯 + 候选需手动确认。
8. 代理式初稿必须经过 writing brief、论点检查、分段成稿和成稿自评四步，并在待复核卡片展示代理运行轨迹。**已满足**：`NativeAIClient.agentDraft(...)` + `AgentDraftTrace`。
9. 代理式初稿必须展示质量门，指出 brief、论点、分段、批评和自检中需要复查的环节。**已满足**：`AgentDraftQualityGateEvaluator` + `PendingDraftReviewCard`。
10. 智能下一步必须输出上下文观察、执行计划和风险提示，并保存到数据库。**已满足**：`WritingAdvisorResult`/`WritingAdvisorRun` 新增字段 + `writing_advisor_runs` 迁移。
11. 写作教练必须支持按最新诊断生成全文改稿候选，且结果进入待复核。**已满足**：`improveDraftFromReview(...)` + `finalizeGeneratedDraft(...)`。

以上 11 条中，第 4 条"输出应有可观察差异"需要作者实际用两种体裁跑同一篇正文来抽检确认，其余 10 条均可从代码逻辑直接确认已满足。



### 18.9 风险与应对


| 风险                      | 影响          | 应对                                                                |
| ----------------------- | ----------- | ----------------------------------------------------------------- |
| 文学性判断主观性强，模型前后判断可能不一致   | 作者信任度下降     | 保留每次诊断的原始记录供对比，强调"参考而非裁决"；配合作者雷区清单，让判断有据可查、可追溯                    |
| 雷区清单由模型聚类归纳，可能出现误判或过度概括 | 长期误导写作方向    | 归纳结果必须经作者手动确认才写入清单，不自动生效；清单条目保留来源诊断，方便随时复核和删除                     |
| 生成后自检增加一次模型调用，拉长等待时间    | 单次操作等待更久    | 自检使用更小的 prompt 和更低输出长度；调用失败静默跳过；长期与流式输出/进度提示（第 3.4 节 P2 既有待办）配合推进 |
| "待复核"状态增加一步交互           | 可能被作者视为多余摩擦 | 仅对代理式初稿/大纲成稿/全文润色这类大范围动作启用；局部改写等低风险操作保持现状直接应用                      |
| 体裁化评价标准增加 prompt 维护成本   | 后续维护复杂度上升   | 通过 `genre` → 评价重点文本的配置化方式实现，不为每个体裁写独立硬编码分支逻辑                      |

以上应对措施均已按设计落地（雷区候选强制人工确认、自检失败静默跳过且不影响主流程、待复核只对大范围生成动作生效、体裁通过配置化的 `genre_focus` 文本而非硬编码分支实现）；实际是否缓解了"作者信任度""维护成本"等长期影响，仍需要作者在真实使用中持续观察。



### 18.10 实施顺序记录

1. 先完成写作教练相关闭环：诊断记忆、防空转、定点改写和作者雷区。
2. 再完成风格系统：体裁化风格、体裁评价重点、同体裁样本注入。
3. 接着完成大范围生成安全机制：生成后自检、待复核、差异对比。
4. 最后补上深度智能链路：智能下一步增强、代理式初稿、代理质量门和按诊断改全文。

**实施记录**：本次是集中改造而不是分批上线，因此没有严格按原提案的批次推进。最终按“诊断闭环 → 风格与上下文 → 待复核安全机制 → 代理式深度写作”的顺序收敛，所有新增能力均已回填到第 5、8、9、10、13 章。

### 18.11 实施总结与范围裁剪说明

1. **分段生成 + 段落级连贯性校验（18.5.1）已裁剪落地**。原提案中的完整方案包含大纲分段、逐段生成、段落衔接校验、流式输出和可能的单段重跑。当前版本先落地最有价值且风险最低的部分：代理式初稿会先生成 writing brief，再做论点检查，然后通过 `sectionDraft` 分段成稿，并用 `draftCritique`/`draftSelfCheck` 给出连贯性复查线索。仍暂缓的是流式逐段输出、段落级重跑和更重的段落衔接校验 UI，原因是这些能力和第 3.4 节的流式输出待办高度重叠，适合在流式方案确定后统一设计。
2. **作者雷区清单未拆分独立表**，维持塞进 `style_profiles.known_pitfalls` JSON 字段的方案（18.6 中列的备选 `author_pitfalls` 表未采用）。理由：当前雷区清单读写路径始终是"整条风格档案一起读、一起存"（`saveStyleProfile`/`editStyleProfile`），没有需要跨风格档案聚合查询雷区，或者对单条雷区做独立索引/分页的场景；JSON 字段能满足现有全部交互（查看/确认/删除/追溯来源），拆表在当前规模下只增加 CRUD 复杂度，没有对应收益。如果未来雷区数量变大、需要跨风格档案统计"哪些雷区反复出现在多个体裁里"，再拆表更合适。
3. **雷区归纳的历史问题来源未按体裁过滤**，`allIssuesHistory()` 现状取该作者全部历史诊断问题，不区分 `genre`。理由：`writing_reviews` 表本身不记录文章体裁，要按体裁过滤需要联查 `articles.genre`（且要求历史文章当时已经补上 `genre`，早期数据大多没有），改造成本和现阶段样本量（单用户、几十条诊断）不成比例。影响：雷区候选可能混入其他体裁的问题模式，但由于候选必须人工确认才会写入清单，风险已经被"人工确认"这道闭环兜住，不构成正确性问题，只是候选列表的精确度还有提升空间。
4. **18.3.4 验收标准第 2 条（两种体裁诊断输出有可观察差异）未做自动化验证**，PRD 原文也说明这条"人工抽检确认，不要求自动化断言"，本次交付到"结构上支持独立配置并注入 prompt"为止，实际差异效果需要作者用真实正文跑两次诊断人工比对。
5. **第 5、8、9、10、13 章已回填**。本章实施结论已经同步到产品原则、功能需求、AI 系统设计、数据模型和验收标准；后续只保留导入导出、流式输出、模型路由、打包签名等明确未做事项。
6. **Claude Code / Codex 式代理写作升级已纳入主线**。这不是另一个备选方案，而是当前智能写作主链路：智能下一步负责观察与计划，代理式初稿负责分步生成，质量门和待复核负责暴露风险，写作教练负责诊断后的再改写。



### 18.12 Claude Code / Codex 式代理写作升级

#### 背景

之前的智能写作仍然偏“按钮式 AI”：输入想法，模型直接返回一篇文章。它能提高速度，但深度不稳定，常见问题是论点没有先被检查、素材缺口没有暴露、长文中段逐渐变空、作者只能在结果出来后凭感觉通读排雷。

Claude Code / Codex 给本产品的启发不是复制代码能力，而是复制工作方式：先读上下文，明确任务状态，列出计划，分步执行，暴露中间判断，最后让用户审查结果。创作工坊已经把这套方式转译为写作代理链路。

#### 已落地设计

1. **智能下一步从建议按钮升级为代理调度器**：`WritingAdvisorResult` 增加 `context_findings`、`execution_plan`、`risk_notes`，并持久化到 `writing_advisor_runs`。
2. **直接初稿升级为代理式初稿**：`NativeAIClient.agentDraft(...)` 串接 `writingBrief`、`argumentCheck`、`sectionDraft`、`draftCritique`，最终产出 `DraftResult`。
3. **待复核暴露运行轨迹**：`PendingDraftReview.agentTrace` 展示工作标题、核心问题、核心主张、目标读者、论点检查指令、缺少的证据/场景、分段摘要和成稿批评。
4. **代理质量门提前暴露风险**：`AgentDraftQualityGateEvaluator` 检查 brief 是否完整、论点检查是否给出指令、分段成稿是否有足够段落摘要、成稿批评是否有效、自检是否提示复查点。
5. **诊断不止能看，还能驱动改稿**：`improveDraftFromReview(...)` 将最近写作诊断转化为全文修订候选，继续进入待复核。
6. **所有代理生成都保留作者确认权**：代理式初稿、按诊断改全文、大纲成稿和全文润色都通过 `finalizeGeneratedDraft(...)` 进入待复核，确认前不得保存为定稿。

#### 产品边界

1. 当前代理链路是本地 SwiftUI App 内的原生工作流，不引入外部 agent runtime。
2. 当前不做 MCP、命令执行、文件系统工具调用或多 agent 协作。
3. 当前 trace 只服务本次待复核，不单独持久化 agent step；后续若要做跨文章代理复盘，再新增 `agent_runs`。
4. 当前质量门是复查提示，不是自动评分系统，不替代作者判断。

#### 验收记录

1. `ModelDecodingTests` 覆盖代理式初稿结构解码、fallback 链路、质量门通过与失败状态。
2. `NativeDatabaseTests` 覆盖 `writing_advisor_runs` 新字段读写，当前 schema version 为 5。
3. `swift test --disable-sandbox --package-path macos/CreativeWorkshopMac` 已通过 25 个单元测试。



## 19. 第三阶段改进建议

第三阶段的重点不再是“能不能生成”，而是让已经落地的代理式初稿、待复核、写作教练、复盘趋势和上下文能力，变成更顺手、更清晰、更像日常写作台的工作流。当前系统已经具备深度写作链路，下一步应该优先降低界面拥挤感、增强结果复用能力，并让写作过程更可追踪。

### 19.1 写作过程与文章编辑拆成两个页签

#### 背景

当前工作区把创作会话、想法、写作方向、标题、摘要、正文、大纲、素材、待复核提示和编辑按钮放在同一纵向画布里。功能完整，但随着代理式初稿、质量门、智能下一步和诊断改稿加入后，主编辑区承载的信息越来越多，作者在真正阅读正文时容易被过程信息打断。

#### 改进方向

将中间主画布拆成两个页签：

1. **写作过程**：承载想法、写作方向、可用素材、代理式初稿按钮、生成选题、生成大纲、智能下一步、待复核摘要、代理运行轨迹入口。
2. **文章编辑**：承载标题、摘要、正文、状态、标签、发布信息、全文润色、局部改写、保存和导出。

这样可以把“思考和生成”与“阅读和编辑”分开：前者更像工作台，后者更像干净的稿纸。

#### 产品要求

1. 默认打开最近使用的页签；新建草稿时默认进入“写作过程”，打开已有正文时默认进入“文章编辑”。
2. “文章编辑”页签中正文区域应保持最大可阅读面积，标题和摘要可以保持在正文上方，但不应挤压正文高度。
3. “写作过程”页签中必须能看到当前待复核状态，避免作者切换后忘记确认或放弃生成结果。
4. 两个页签共享同一篇文章状态，切换页签不得触发保存、重置选区或丢失未确认待复核内容。
5. 右侧 Inspector 继续保留上下文、诊断、发布、资料等视图；中间页签只负责主工作流分区，不替代 Inspector。

#### 验收标准

1. 用户可以在“写作过程”和“文章编辑”之间切换。
2. “文章编辑”页签下正文可视高度明显大于当前混合布局，适合作为主要编辑窗口。
3. 运行代理式初稿或大纲成稿后，待复核提示在两个页签都不会丢失。
4. 已选中的正文片段在切换到“文章编辑”页签后仍可用于局部改写。



### 19.2 写作教练增加一键复制按钮

#### 背景

写作教练已经能输出评分、一句话诊断、优点、问题、修改顺序、训练重点、已解决问题和读者视角等内容。这些内容很适合复制到 Obsidian、微信草稿、复盘文档或外部 AI 对话中继续分析，但当前缺少“一键复制完整诊断”的入口。

#### 改进方向

在写作教练区域增加“复制”按钮，将当前诊断结果整理为 Markdown 后写入剪贴板。

建议复制内容格式：

```markdown
# 写作教练诊断

文章：{title}
时间：{created_at}
评分：{overall_score}

## 一句话诊断
{summary}

## 优点
- ...

## 优先修改项
1. [{severity}] {dimension}
   原文：{excerpt}
   问题：{problem}
   建议：{suggestion}

## 修改顺序
1. ...

## 训练重点
- ...

## 风格观察
- ...

## 较上次已解决
- ...
```

#### 产品要求

1. 写作教练卡片顶部增加复制按钮，图标优先使用系统 `doc.on.doc`。
2. 复制内容应包含当前展示的完整诊断，而不是只复制摘要或评分。
3. 没有诊断结果时复制按钮禁用，并提示“暂无可复制的诊断”。
4. 复制成功后给出轻提示，例如状态栏显示“已复制写作教练诊断”。
5. 复制格式使用 Markdown，方便进入 Obsidian、公众号草稿和其他 AI 工具。
6. 后续可扩展为“复制完整诊断”“复制修改清单”“复制训练重点”三个选项，但第一版先做完整复制。

#### 验收标准

1. 有诊断结果时点击复制按钮，系统剪贴板中出现完整 Markdown 诊断。
2. 复制内容至少包含：文章标题、诊断时间、评分、一句话诊断、优点、问题列表、修改顺序、训练重点。
3. issue 中存在 `excerpt` 时，复制内容保留对应原文片段，便于外部复盘。
4. 无诊断结果时按钮不可用，不出现空内容复制。



### 19.3 第三阶段其他建议方向

#### 19.3.1 自动保存与草稿恢复

代理式写作链路已经较长，待复核和多版本候选也会让一次写作持续更久。第三阶段应增加自动保存和异常恢复：

1. 定时保存当前标题、摘要、正文、大纲、素材和待复核状态。
2. App 异常退出后，重启时提示恢复未保存草稿。
3. 自动保存不替代“保存文章”，只作为安全网。

#### 19.3.2 代理运行记录可复盘

当前 `AgentDraftTrace` 只服务本次待复核。后续可以考虑新增 `agent_runs` / `agent_steps`，把 brief、论点检查、分段成稿、自评和质量门结果持久化，用于复盘“哪类题材生成质量最好、哪类题材最常触发质量门”。

#### 19.3.3 写作教练导出与复盘档案

在一键复制之后，可以继续支持：

1. 导出单篇文章复盘 Markdown。
2. 导出最近 30 天写作教练报告。
3. 将训练重点汇总成“本周写作训练计划”。

#### 19.3.4 更明确的编辑模式

在“文章编辑”页签中进一步区分：

1. **专注写作**：隐藏大部分按钮，只保留正文、标题、保存。
2. **修改润色**：显示全文润色、局部改写、版本差异。
3. **发布整理**：显示摘要、标签、发布物料、数据录入。

这可以在页签拆分之后逐步推进，不需要一次完成。

#### 19.3.5 流式输出与可取消生成

当前模型调用以完整结果返回为主。第三阶段若继续提升长文体验，应支持：

1. 长文生成时显示阶段进度。
2. 允许取消正在执行的模型调用。
3. 流式输出正文，但仍保留待复核机制。
4. 代理式初稿每个步骤完成后可见，避免作者等待一个黑盒结果。

**实施记录**（2026-07-05，第 22 章任务 9）：`OpenAICompatibleModelGateway.stream(_:)` 已实现，`AIWorkflowRunner.run` 支持 `onPartialOutput` 增量回调并沿 `WorkflowEngine`/`NativeAIClient` 贯通到 `WorkshopStore`；生成大纲、大纲成稿、全文润色、局部改写执行中通过状态栏显示流式进度。取消沿用既有 `run(cancellable:)` + `Task.checkCancellation` 机制，待复核语义不变。



### 19.4 第三阶段优先级建议

| 优先级 | 改进项 | 理由 |
| --- | --- | --- |
| P0 | 写作过程 / 文章编辑双页签 | 直接改善主编辑窗口阅读体验，降低当前界面拥挤感 |
| P0 | 写作教练一键复制 | 实现成本低，复用价值高，方便进入外部复盘和知识库 |
| P1 | 自动保存与草稿恢复 | 降低长文写作和待复核过程中的数据风险 |
| P1 | 流式输出与可取消生成 | 改善长模型调用等待体验 |
| P2 | 代理运行记录持久化 | 让代理链路从单次运行变成可复盘资产 |
| P2 | 写作教练导出报告 | 扩展长期训练系统价值 |



## 20. 第四阶段改进提案：迈向"少改/零改即可发表"的智能写作（待审查）

状态：已实施，含后续修订。20.2～20.6 已按第 18 章的格式在各节回填"实施记录"；20.6 第 3 点（多候选优选/模型分层与流式输出合并）仍未落地，见该节实施记录。

### 20.0 前提盘点：系统现在已经具备什么

经过第 18 章改造与第三阶段演进，当前系统已具备"一次生成 + 人工多轮改"所需的全部零件：

1. 代理式初稿链路：brief → 论点检查 → 分段成稿 → 自我批评（`NativeAIClient.agentDraft`），配质量门五项检查（`AgentDraftQualityGate`）。18.5.1 当时暂缓的"分段生成"已随这条链路实际落地。
2. 生成后自检（`draftSelfCheck`）与编辑器内高亮提示。
3. 写作诊断闭环：诊断记忆（`resolved_from_last`）、防空转、定点改写、按诊断改全文，全部走"待复核"人工确认后才落地。
4. 体裁化风格（`genre`/`genre_focus`）、作者雷区清单（`known_pitfalls`）、同体裁历史文章自动注入 few-shot 样本（`resolveStyle()`）。
5. 能力雷达（`WritingDimensionAnalytics`）、读者视角模拟、选题去重、版本快照（`draft_versions`）与差异对比（`TextDiff`）。

第四阶段的命题因此不是"再加一种生成"，而是：**让这些零件在进入"待复核"之前自动多转几圈，把人工检查从"发现问题"变成"确认没有问题"**。

### 20.1 目标、北极星指标与原则演进

目标：AI 产出达到"作者只需简单修改、甚至无需修改即可直接发表"的水平。

这句话必须有可测量的定义，否则无法验收。建议引入两个自动统计指标（数据来自现有表 + 20.7 的少量新增）：

1. **发表前人工编辑量**：文章状态翻为"已发布"时，把当时正文与该文章最近一次已确认的 AI 生成版本（`draft_versions` 对应记录的 `after_content`）做字符级 diff，记录增删字符数与编辑比例。
2. **零改动/轻改动发表率**：编辑比例 ≤1% 记为"零改动"，≤10% 记为"轻改动"，按月统计占比趋势。这是第四阶段唯一的北极星指标——所有改进项最终都要回答"它让这个比例上升了吗"。

原则演进说明：第 18.2.1 条"AI 不做最终判断，只降低人工判断的成本"**不修改、继续成立**。第四阶段追求的不是取消人工检查，而是让人工检查越来越多地"一次通过"：所有自动迭代都发生在"待复核"之前，最终产出仍进入 18.4.1 的 pending → confirmed 闭环，作者仍是唯一有权定稿和发布的人。

优先级总览：

| 优先级 | 改进项 | 一句话理由 |
| --- | --- | --- |
| P1 | 20.2 自动迭代修订闭环 | 复用现有零件最多，对"少改即可发表"贡献最直接 |
| P1 | 20.3 个人语料检索增强 | 解决文学质量的根因：真实细节，而不是面熟的虚构 |
| P2 | 20.4 作者编辑行为学习 | 把每次人工修改变成系统资产，编辑量随使用递减 |
| P2 | 20.5 发表前终审门 | 覆盖错字、引文、一致性这类"发表安全"盲区 |
| P3 | 20.6 多候选自动优选 + 模型分层 | 进一步抬高质量上限，成本换质量，需流式输出配合 |

### 20.2 P1：自动迭代修订闭环（生成 → 诊断 → 修订 → 复评，自动多轮）

现状：写作诊断、按诊断改全文、自检、质量门都已存在，但每一轮都要作者手动触发。18.1 第 2 条的真实数据显示，人工驱动的迭代收敛很慢（同一篇文章 4 次诊断，分数 72→72→72→75）。模型能发现问题、也能按问题改，缺的只是"自动把这两步串起来转到收敛"。

改造方向：

1. 新增"深度成稿"模式（作用于代理式初稿之后，也可从既有正文发起）：自动执行「写作诊断 → 若存在高/中严重度 issue 或命中作者雷区 → 按诊断修订 → 复评」的循环，直到满足退出条件。
2. 退出条件（全部可配置）：a) 无高严重度 issue 且未命中任何 `known_pitfalls`；b) `overall_score` 达到目标分（默认 85），或连续两轮提升不足 3 分（收敛判定，防止无效空转）；c) 达到最大轮数（默认 3 轮）。
3. 复评 prompt 必须强制逐条核销上一轮 issue（复用 `resolved_from_last` 机制），防止模型"自己夸自己"式的虚假收敛。
4. 每一轮的诊断结果、修订说明、分数变化写入持久化的运行轨迹（与 19.3.2 的 `agent_runs` 合并实施）；"待复核"卡片展示迭代摘要："共迭代 N 轮，分数 72→86，最后一轮剩余问题：…"。作者据此决定确认或放弃。
5. 迭代中任何一环调用失败，直接以当前最好的版本进入待复核，不阻塞、不清空已有内容（沿用第 12 章非功能要求）。

涉及模块：`WorkshopStore.swift`（新增编排方法，复用写作诊断与按诊断改全文的既有实现）、`WorkshopModels.swift`（迭代轨迹结构）、`NativeDatabase.swift`（`agent_runs`/`agent_steps` 表）、`InspectorView.swift`（待复核卡片的迭代摘要）。

验收标准：

1. 深度成稿产出进入待复核时，必须附带每轮分数与剩余问题清单，作者不点开原始记录也能看懂"改了几轮、还剩什么"。
2. 迭代轮数不得超过配置上限；任何一轮失败都必须交付当前最好版本，不得空手而归。
3. 同一篇文章走深度成稿后再人工触发一次写作诊断，高严重度 issue 数应明显低于单轮生成（人工抽检确认）。

**实施记录**：落地为 `DeepDraftCoordinator.swift`，编排「写作诊断 → 按诊断修订 → 复评」循环，退出条件（无高严重度 issue 且未命中雷区 / 达到目标分或连续两轮提升不足 3 分 / 达到最大轮数）均按方向 2 实现为可配置参数。复评阶段复用 `resolved_from_last` 机制强制核销上一轮 issue。迭代轨迹落 `agent_runs`/`agent_steps` 表（与 19.3.2 合并实施），待复核卡片展示各轮分数与剩余问题摘要。任一环调用失败时以当前最好版本进入待复核，不清空已有内容。

### 20.3 P1：个人语料检索增强（把真实素材接进分段成稿）

现状：few-shot 样本解决的是"腔调像作者"，解决不了"细节是作者的"。诊断历史反复出现的"情绪悬浮、细节不具体、意象面熟"（18.1 第 1、4 条），根因是生成时模型手里没有作者的真实经验片段。素材库（`ideas`）已经在积累数据，但目前只以整段 `materials` 文本粗放拼进 prompt，长素材、多素材场景下命中率很低。

改造方向：

1. 建立本地片段索引：把素材（`ideas`）与已发布文章正文切成 200～400 字的片段，入 `fragments` 表。
2. 生成时按段检索：代理式初稿的每个 section 生成前，用该段主题句检索 top-3 相关片段注入该段 prompt，并明确要求"优先使用这些真实素材中的细节，不得虚构相似场景替代"。
3. 检索实现分两版：第一版用词法相似度（复用 `TopicDeduplicator` 的 bigram Jaccard 思路，加关键词命中加权），零新依赖、零额外网络调用；第二版再考虑接 OpenAI 兼容的 embedding 端点（若当前服务商不提供 embedding 接口，需允许为该功能单独配置端点），默认关闭。
4. 命中的片段在待复核卡片列出（"本次引用了你的 3 条素材"），作者可核对是否被误用、断章取义。

涉及模块：`NativeDatabase.swift`（`fragments` 表 + 切片与检索查询）、新增 `FragmentRetriever.swift`（纯函数模块，可独立测试）、`NativePrompts.swift`（分段成稿 prompt 注入检索块）、`NativeAIClient.swift`（agentDraft 各 section 传入检索结果）、`InspectorView.swift`（引用素材展示）。

验收标准：

1. 素材库存在相关素材时，深度成稿的产出必须能在待复核卡片追溯到被引用的素材条目。
2. 检索无命中或不可用时，生成流程不受任何影响。
3. 第一版切片与检索为纯本地操作，不新增网络依赖。

**实施记录**：新增 `FragmentRetriever.swift`（纯函数模块，词法相似度检索，复用 `TopicDeduplicator` 的 bigram Jaccard 思路）与 `fragments` 表（素材/已发布文章切片，200～400 字）。代理式初稿分段生成时按段主题句检索 top-3 片段注入该段 prompt，并要求"优先使用真实素材细节，不得虚构相似场景替代"。命中的片段在待复核卡片列出可追溯来源。第二版 embedding 检索按方向 3 保留为默认关闭、暂未实现，当前仅落地词法版。

### 20.4 P2：作者编辑行为学习（从改动 diff 中归纳风格校准规则）

现状：作者每次确认待复核后的手工修改、每次"放弃"某个候选的决定，都是最真实的偏好信号，目前全部流失。雷区清单只覆盖"诊断发现的问题"，不覆盖"作者看到就顺手改掉的表达"——而后者才是"零改动发表"的最后一公里。

改造方向：

1. 文章发布时自动计算"最近一次 AI 确认稿 → 发布稿"的 diff（复用 `TextDiff`），连同编辑比例存入 `edit_records` 表。这一步同时为 20.1 的北极星指标供数。
2. 积累到一定篇数后，新增"归纳编辑偏好"动作（机制完全类比 18.3.3 的雷区归纳）：把高频改动模式（总被删掉的句式、总被替换的用词、总被压缩的段落类型）交给模型聚类，产出候选"风格校准规则"。
3. 候选规则经作者逐条确认后写入 `StyleProfile` 新增的 `learned_preferences` 字段（归纳自动、生效必须人工确认，与 `known_pitfalls` 同一套约束），确认后注入生成类 prompt。
4. 复盘区按月给出一行摘要："本月零改动发表率 X%，较上月 ±Y%"，让作者看到系统是否真的越用越懂自己。

涉及模块：`NativeDatabase.swift`（`edit_records` 表 + 统计查询）、`WorkshopStore.swift`（发布时触发记录、归纳动作）、`NativePrompts.swift`（归纳 prompt + 规则注入）、`SettingsView.swift`（规则确认 UI，与雷区清单同区展示）。

验收标准：

1. 状态翻为"已发布"时自动记录编辑量，对作者无感，记录失败不阻塞发布。
2. 校准规则未经作者确认不得注入任何 prompt。
3. 复盘区能看到零改动/轻改动发表率的月度变化。

**实施记录**：`edit_records` 表落地，文章发布时自动记录"最近一次 AI 确认稿 → 发布稿"的 diff 与编辑比例（同时为 20.1 北极星指标供数，`PublishingMetricsRecorder` 负责快照统计）。`WorkshopStore.summarizeEditPreferences()` 归纳高频改动模式为候选校准规则，作者逐条确认后写入 `StyleProfile.learned_preferences`（机制同 `known_pitfalls`，候选不经确认不注入 prompt）。`editRecordStats`/`editRecordMonthlySummary` 在复盘区展示零改动/轻改动发表率的月度变化。

### 20.5 P2：发表前终审门（错字、引文、一致性的机器初审）

现状：质量门只覆盖生成过程信号（brief/论点/分段/自我批评/自检），不覆盖"发表安全"：错别字（18.1 中"葬花呤"错字是写作诊断顺带发现的，属于运气）、引文准确性（"经典文本再解读"体裁的硬要求）、标题-正文-摘要一致性。这些恰恰是"不用再读一遍就敢发"的前提。

改造方向：

1. 新增 `prePublishAudit` 工作流：作者把状态改为"已发布"前自动运行一次终审，输出结构化报告，逐项"通过/建议复核"：错别字与病句清单（含原文位置）、引文核对、标题-正文-摘要一致性、作者雷区最终扫描。
2. 引文核对采用"模型找引文 + 本地比对"分工：模型只负责标出"哪些是引文"，字符串比对交给本地逻辑（与素材库、既有正文匹配），找不到匹配即标黄提示人工核对，不做自动改写。
3. 错字/病句项支持一键跳转到原文位置（复用 18.3.1 的 `locateExcerpt` 定位机制），可直接接定点改写。
4. 全部通过时显示"终审通过，可直接发表"；存在黄项时作者仍可强制发布——AI 只提示、不拦截，遵守 18.2.1。

涉及模块：`NativePrompts.swift`/`NativeAIClient.swift`（新增工作流）、`WorkshopStore.swift`（`updateSelectedArticleStatus` 发布路径前置串接）、`InspectorView.swift`（终审报告卡，样式复用质量门清单）、`WorkshopModels.swift`（报告结构）。

验收标准：

1. 发布动作前自动产出终审报告；终审调用失败不阻塞发布，只提示"终审未完成"。
2. 错字项能定位原文并一键跳转。
3. 引号内容在素材/正文库中找不到匹配时必须标黄。

**实施记录**：新增 `PrePublishAuditCoordinator.swift` 与 `prePublishAudit` 工作流，产出结构化终审报告（错别字/病句、引文核对、标题-正文-摘要一致性、雷区最终扫描），落在 `articles.audit_report` 字段（发布路径前置串接，`updateSelectedArticleStatus` 触发）。引文核对采用"模型标引文 + 本地字符串比对"分工，找不到匹配标黄提示人工核对，不自动改写。错字/病句项复用 `locateExcerpt` 定位机制一键跳转到定点改写。终审调用失败不阻塞发布，只提示"终审未完成"；全部通过时显示"终审通过，可直接发表"，存在黄项仍可强制发布。

### 20.6 P3：多候选自动优选与模型分层路由

1. **多候选自动优选**：现有"生成 3 个候选"需要作者逐个恢复预览、自行比较。升级为：生成 N 个候选后追加一次"评委"调用（按 `genre_focus`、雷区、诊断维度打分排序），默认只把最优候选送入 20.2 的迭代闭环，其余保留在版本列表可随时切换；评委的排序理由展示在待复核卡片。
2. **模型分层路由**：为"高质量关键步骤"（终评诊断、最终润色、评委）与"高频廉价步骤"（分段草稿、自检、检索）配置不同模型——`ModelConfig` 扩展为按工作流可覆盖。用便宜快的模型跑内循环、最强的模型把最后一道关，在控制成本的同时抬高质量上限。
3. 两项都会显著拉长单次操作的调用链，应与 19.3.5 的流式输出/可取消生成合并规划，不建议在其之前单独实施。

**实施记录**：第 1 点（多候选自动优选）已落地——`NativeWorkflowCatalog.judgeDraftCandidates` 对生成的候选按 `genre_focus`、雷区、诊断维度打分排序，最优候选送入 20.2 迭代闭环，排序理由展示在待复核卡片（`WorkshopStore` 中 `candidateJudgement` 落点）。第 2 点（模型分层路由）已落地——`ModelConfig.workflowOverrides` 支持按工作流覆盖模型/端点。第 3 点原判"与流式输出合并规划、暂不实施"，现已随第 22 章任务 9 落地：`OpenAICompatibleModelGateway.stream(_:)` 已实现真实流式，`AIWorkflowRunner` 经 `onPartialOutput` 支持增量输出，详见 19.3.5 实施记录。

### 20.7 数据模型变更汇总

| 表 / 字段 | 变更 | 用途 |
| --- | --- | --- |
| `agent_runs` / `agent_steps` | 新表，持久化代理与迭代轨迹（与 19.3.2 合并实施） | 20.2 迭代审计与复盘 |
| `fragments` | 新表，素材/文章切片与检索元数据 | 20.3 个人语料检索 |
| `edit_records` | 新表，发布时"AI 确认稿 vs 发布稿"diff 统计 | 20.1 北极星指标、20.4 偏好学习 |
| `style_profiles.learned_preferences` | 新增 JSON 字段，已确认的风格校准规则 | 20.4，机制同 `known_pitfalls` |
| `articles.audit_report` | 新增 JSON 字段（可选），最近一次终审报告快照 | 20.5 |
| `ModelConfig` | 扩展为按工作流覆盖模型 | 20.6 |

### 20.8 风险与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 自动迭代成倍增加调用次数与等待时间 | 单次深度成稿可能 8～12 次调用 | 轮数上限 + 收敛早停 + 模型分层；流式/可取消（19.3.5）先行；保留"快速成稿/深度成稿"两档供选择 |
| 模型自评自改陷入同质化循环（自己给自己打高分） | 分数虚高、问题未真正解决 | 复评强制逐条核销上一轮 issue（复用 `resolved_from_last`）；北极星指标看的是发布时的真实编辑量，不看模型自评分；人工待复核永远兜底 |
| 编辑偏好学习样本少，归纳易过拟合 | 错误规则长期误导生成 | 与雷区清单同一约束：候选必须人工确认；每条规则保留来源 diff，可追溯、可随时删除 |
| 引文核对依赖素材库完整性 | 误报（原文不在库里）或漏报 | 只做"找不到匹配就标黄提醒"，不自动改写；报告中明确标注核对范围 |
| "零改动发表"目标可能诱导作者放松检查 | 质量责任悄悄转移给 AI | 终审全绿也只显示"可直接发表"，发布动作永远由作者执行；指标用于观察趋势，不设为强制门槛 |

### 20.9 建议执行顺序

1. 先落度量：`agent_runs` 持久化 + `edit_records` 编辑量统计（20.7）。先有"发表前编辑量"这把尺子，再谈优化——否则第四阶段所有改进的效果都无法验证。
2. 20.2 自动迭代修订闭环：复用现有零件最多，预期对北极星指标贡献最直接。
3. 20.3 个人语料检索（先做词法版）：与 20.2 正交，解决"细节真实"这个文学质量根因。
4. 20.4 编辑行为学习、20.5 发表前终审门：依赖 1 的数据积累，适合在前两项跑顺后启动。
5. 20.6 多候选优选与模型分层：与流式输出/可取消（19.3.5）合并规划，最后做。



## 21. AI 智能架构评审：是否需要重大重构（建议，待审查）

状态：架构评审结论 + 重构建议，R1～R4 已完成，R5 进行中。本章基于 2026-07-02 对全部 Swift 源码的实测检查（文件规模、依赖方向、重复模式、测试覆盖），供审查。

### 21.0 评审结论

**不需要推倒重来式的"重大重构"。** 数据层、UI 层、"本地优先 + 直连模型 API"的总体架构是健康的，方向正确，不该动。

**但存在一处集中的结构债：工作流接入路径。** 每新增一个 AI 工作流，要在 6～8 个文件里手写一遍几乎相同的样板（结果类型 + prompt 构造 + 兜底孪生 + 客户端透传方法 + 解析特判 + Store 编排 + UI）。第 18 章新增 3 个工作流、第三阶段新增代理链路时，这个模式已经各复制了一轮；第 20 章的自动迭代闭环需要**程序化地组合与循环调用工作流**，在现有结构上做等于把复制粘贴再放大一倍。因此建议：**在第 20 章动工之前，先做一次范围明确的"工作流内核收敛"（R1～R5），采用逐个迁移的绞杀式策略，不冻结功能、不整体重写。**

### 21.1 现状体检（实测数据）

| 证据 | 数值 | 说明 |
| --- | --- | --- |
| `WorkshopStore.swift` | 2589 行 / 64 个 `@Published` / 约 100 个方法 | UI 状态、工作流编排、持久化协调三种职责混在一个类型里，所有新功能默认落这里 |
| `recordAICall` 样板 | Store 内重复 16 处 | 每个工作流手抄一遍"调用 → 记录 → 应用结果 → statusText"四段式 |
| `NativeAIClient.swift` | 14 个公开方法 | 绝大多数是"取 prompt → 调 runner → 包装响应"的透传，逐个手写 |
| `AIWorkflowRunner.decodeModelJSON` | 对 9 个结果类型逐一 `if T.self ==` 特判 + `as!` 强转 | 解析降级逻辑与类型硬编码，新工作流的降级行为靠往 if 链里加分支 |
| `NativeFallbacks.swift` | 20 个静态方法 | 每个工作流一个兜底孪生，新增工作流时容易漏配 |
| 写死的调用参数 | `temperature 0.75`、`stream: false`、`timeout 90` | 无法按工作流调节；20.6 的模型分层、19.3.5 的流式在此结构上无处安放 |
| `aiClient = NativeAIClient()` | Store 内部直接实例化 | AI 调用无法替身（stub），导致编排层 0 测试 |
| 测试分布 | 21 个测试全部在数据库层与解码层 | Store 约 100 个方法（含所有智能编排逻辑）无任何自动化测试保护 |

新增一个工作流的实际改动面（以 18.3.5 的 `draftSelfCheck` 为实例）：`WorkshopModels`（结果/响应结构 + `PromptTemplateKey`）→ `NativePrompts`（builder + 模板种子）→ `NativeFallbacks`（兜底）→ `NativeAIClient`（方法）→ `AIWorkflowRunner`（解析特判）→ `WorkshopStore`（编排 + 状态）→ 视图。**7 个文件，全部手写，没有任何一步是声明式的。** 这就是"合规路径比绕路贵"的典型状态——目前靠纪律维持一致性，而第 20 章会把调用链长度翻倍。

### 21.2 明确不需要重构的部分

以下部分经检查判定为健康，本轮**不动**，避免为重构而重构：

1. **`NativeDatabase.swift`（1675 行）**：行数大但职责单一（持久化唯一入口），schema 版本迁移机制清晰，是全项目测试覆盖最好的模块。除第 20 章的新表外不做结构调整。
2. **SwiftUI 视图层**：`InspectorView` 1390 行偏大，但视图属于低稳定性表面，改动便宜、无跨模块依赖，按需把卡片拆成独立文件即可，不立项。
3. **本地优先架构本身**：单用户、无服务端、SQLite + Keychain + 直连 API 的形态与产品定位（第 3 章）完全匹配，不引入服务端、不换存储。
4. **不引入重型框架**：不需要 LangChain 式的 agent 框架、不迁移 SwiftData、不改造成 TCA。现有问题是"重复"而不是"缺框架"，引入大框架只会用新概念换旧概念。
5. **已有的取消机制**：`run(_:cancellable:)` + `currentOperationTask` + runner 内 `Task.checkCancellation` 已经工作，R4 只需保留它，不重做。

### 21.3 建议的重构项（R1～R5）

#### R1. 依赖可注入，先给编排层上测试（最先做，成本最低）

症状：`aiClient`/`contextBuilder` 在 Store 内直接实例化，AI 调用无法替身，编排逻辑（防空转判断、待复核状态机、确认/放弃闭环）全靠人工回归。

方案：为 `NativeAIClient` 抽协议（或直接注入闭包表），`WorkshopStore.init` 改为注入依赖，默认参数保持现有行为不变。随后为最关键的三条编排链补测试：诊断防空转、待复核确认/放弃、定点改写的"正文已变化拒绝写入"。

边界：不改任何业务行为；不追求覆盖率数字，只保护状态机。

验收：不改 UI 的前提下，能用假 AI 客户端跑通上述三条链路的单元测试。

**实施记录：R1 已完成**。`WorkshopStore.init` 已改为注入依赖（`AIWorkflowExecuting` 协议），默认参数保持原有行为；诊断防空转、待复核确认/放弃、定点改写"正文已变化拒绝写入"三条编排链均已补齐单元测试。

#### R2. 统一工作流管道：把"7 个文件的手写接入"收敛为"1 份声明"（核心项）

症状：见 21.1。每个工作流是一条手写的平行路径，违反"一条主路径，功能向路径沉降"的原则。

方案：新增 `WorkflowDescriptor`（声明：模板 key、prompt 构造闭包、兜底闭包、解析降级闭包、是否记录 `ai_calls`）与一个执行引擎。引擎统一负责：构造 prompt → 调模型 → 解析（含降级）→ 失败兜底 → `recordAICall` → 返回类型化结果。第 20.2 的迭代闭环即"引擎按序/按条件执行多个 descriptor"，不再需要在 Store 里手写循环样板。

**配套退役清单**（新抽象必须换走旧概念，否则只是加层）：`NativeAIClient` 的 14 个透传方法逐个删除；`AIWorkflowRunner.decodeModelJSON` 的 9 类型 if 链拆散进各 descriptor 的降级闭包；Store 内 16 处 `recordAICall` 样板删除。`NativeFallbacks` 的函数保留，但改为经 descriptor 引用——新工作流漏配兜底会在编译期暴露而不是运行时缺失。

边界：不改 prompt 内容、不改任何模型行为、不改数据库写入格式（`ai_calls` 记录字段保持不变，历史数据可比）。

验收：新增一个演示工作流只需 1 个 descriptor 声明 + 1 处 UI 接入；现有全部工作流迁移后行为与迁移前一致（对照 `ai_calls` 记录抽查）。

**实施记录：R2 已完成**。`WorkflowDescriptor`/`WorkflowEngine`（`WorkflowEngine.swift`）与 `NativeWorkflowCatalog.swift` 已落地，全部工作流以 descriptor 形式声明。配套退役清单已执行：`NativeAIClient` 已降级为兼容 facade，不再持有高层工作流透传方法（`script/architecture_guard.sh` 的 `client_passthrough_hits` 检查项对此把关）；`decodeModelJSON` 的类型 if 链已拆散进各 descriptor 的降级闭包；Store 内 `database.recordAICall` 手写样板已清除，改由 `WorkflowEngine` 统一记录。

#### R3. ContextPackage 统一注入（完成 9.3 / 17.2 / 18.7 的未竟部分）

症状：`ContextPackage` 已存在且 18.7 做了 typealias 收敛，但多数 prompt 构造函数仍接收零散的长参数列表（title、summary、content、outline、idea、direction、style、previousReview……），每加一种上下文（如 20.3 的检索片段、20.4 的校准规则）要改 N 个函数签名。

方案：随 R2 迁移，把 prompt 构造闭包的输入统一为 `ContextPackage`（按需扩字段），一处新增、处处可用。

验收：20.3 的"检索片段注入"只需在 `ContextPackage` 加一个字段 + 相关 prompt 模板读取它，不改任何函数签名。

**实施记录：R3 已完成**。`ContextPackage`（`WorkshopModels.swift`）已扩展为 descriptor 的统一入参，20.3 的检索片段等新增上下文均以加字段方式接入，未改动函数签名。

#### R4. 模型网关协议：把传输层从 runner 里剥出来

症状：`AIWorkflowRunner` 同时负责传输（URLSession + `/chat/completions`）、解析、降级、摘要，`stream: false`/`temperature`/超时写死，`ModelConfig` 全局唯一。19.3.5（流式/可取消）和 20.6（按工作流分层选模型）都要在这里动刀，现在不分层，届时每个都是侵入式改动。

方案：抽 `ModelGateway` 协议（同步完成 + 流式两个方法；按调用传入模型参数），OpenAI 兼容实现为唯一实现。`ModelConfig` 扩展为"全局默认 + 按工作流覆盖"（20.7 已列）。流式实现本身可以等 19.3.5 排期，本轮只把接口位置留对。

边界：不实际实现第二家模型供应商；不做重试/限流等当前用不到的能力。

验收：runner 不再包含 URLSession 细节；替换/新增模型端点不触碰解析与编排代码。

**实施记录：R4 已完成**。`ModelGateway.swift` 已抽出协议（同步 `complete` + `stream` 两个方法），OpenAI 兼容实现为唯一实现；`ModelConfig.workflowOverrides` 已支持按工作流覆盖模型（20.6 已消费）。`stream(_:)` 起初仅留接口位（抛 `streamingNotImplemented`），后已随第 22 章任务 9 实现真实流式（见 19.3.5 实施记录）。

#### R5. WorkshopStore 瘦身（随 R2 渐进，不设专门工期）

症状：见 21.1 第一行。2589 行的单一 `@MainActor` 类型是目前唯一的"上帝对象"，第 19/20 章功能继续落进去只会加速膨胀。

方案：不做一次性拆分。随 R2 逐工作流迁移，编排逻辑自然移入引擎层与少数领域服务（如"待复核状态机"可独立成类型），Store 收敛为"UI 状态 + 绑定 + 转发"。目标水位：迁移完成后 Store 降到 1200 行以内，`@Published` 数量减少（部分状态随编排下沉为返回值）。

验收：以行数与职责抽查为准，不设硬性截止——但第 20 章新功能一律不得在 Store 里手写编排（见 21.5 护栏）。

**实施记录：R5 进行中**。`WorkshopStore.swift` 当前 2635 行，已超过 21.5 设定的迁移期护栏警戒线（2600 行，`script/architecture_guard.sh` 对此只告警不阻断），距最终目标（1200 行）仍有较大差距；R2/R3/R4 已完成后 Store 内编排样板已大幅收敛，但瘦身本身尚未达标，需持续推进。

### 21.4 执行策略与顺序

采用绞杀式迁移，全程不冻结功能、每步保持 `swift build`/`swift test` 绿：

1. **R1**（半天级）：注入 + 三条关键链路测试。这是后续所有改动的安全网。
2. **R2 + R3**（主体工作）：先搭 descriptor/引擎并让**新**工作流走新路径；再按"低风险 → 高风险"逐个迁移旧工作流（建议顺序：readerPerspective/pitfallSummary 这类旁路 → topics/outline → draft 类 → writingReview/agentDraft 主链）。每迁移一个删一段旧样板。
3. **R4**（接口先行）：在 R2 引擎成形时同步抽 `ModelGateway`，流式实现留给 19.3.5 排期。
4. **R5**：随 2 自然发生，迁移全部完成后做一次收尾清理。
5. **与第 20 章的衔接**：20.9 第 1 步（度量基建）不依赖本章，可并行；20.2（自动迭代）**必须**在 R2 之后动工——迭代闭环是 descriptor 组合的第一个真实消费者，也是这次重构的直接验收场景。

### 21.5 轻量护栏（防止回潮）

规模与人手（单人项目）决定护栏必须便宜，只设三条、全部可机器检查或一眼可查：

1. 视图层禁止直接引用 `NativeAIClient`/`ModelGateway`/`AIWorkflowRunner`（只能经 Store），用一个 grep 脚本挂进 `script/build_and_run.sh` 或 CI，违规即构建失败。
2. 新增 AI 工作流必须以 descriptor 形式接入；出现"绕过引擎直接调 runner"的代码视为架构缺陷处理。
3. `WorkshopStore.swift` 设行数警戒线（迁移期 2600，完成后 1200），超线时脚本告警——只告警不阻断，作为"该还债了"的信号。

### 21.6 风险与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 迁移期间引入行为回归（prompt 拼装差异、降级行为差异） | 生成质量悄悄劣化 | R1 先行提供测试安全网；逐工作流迁移并对照 `ai_calls` 的输入摘要抽查；prompt 内容一字不动 |
| 重构与第 20 章功能开发争抢时间 | 两头都慢 | 只有 20.2/20.6 依赖本章；20.9 第 1 步（度量）与 20.3 词法检索可并行推进 |
| 抽象过度，引擎变成第二个框架 | 用新复杂度换旧复杂度 | descriptor 只收敛已存在的五段样板，不新增能力；每个新概念绑定退役清单（21.3 R2），净概念数下降 |
| 单人项目护栏执行走样 | 规则名存实亡 | 护栏全部脚本化，不依赖记忆；只设 3 条，宁少勿虚 |



## 22. Agentic Harness 全盘审查与改进提案（已实施）

状态：已实施。本章基于 2026-07-04 对全部 Swift 源码的逐文件审查（编排协调器、提示词层、网关层、质量门、检索与记忆闭环、测试与护栏脚本），回答两个问题：**agentic harness 到底有没有实现？它对写作质量有没有可证明的提高？** 审查结论经作者确认后拆解为 10 个任务提示词（见 `创作工坊-22章改进-执行提示词.md`），2026-07-05 全部执行完成并复核：99 项单元测试通过（含 Eval 目标 5 项），`architecture_guard.sh` 通过（附警告：`WorkshopStore.swift` 2635 行已超 2600 迁移警戒线）。唯一未实施项为 22.2.3（P2，未列入本轮任务）。各节末尾附实施记录；本章正文保留审查时点的原始表述，以下描述的缺陷均已修复。

### 22.0 审查结论

**问题一：agentic harness 有实现吗？——有"编排式 harness"，没有"代理式循环"，且有三处"代理"名不副实。**

已经真实落地的是一套相当完整的**工作流编排基础设施**：声明式工作流（`WorkflowDescriptor` + `WorkflowEngine` + `NativeWorkflowCatalog`，第 21 章 R2 已完成且有 `architecture_guard.sh` 护栏）、固定四步初稿管线（`AgentDraftCoordinator`：brief → 论点检查 → 分段成稿 → 自我批评整合）、评审-修订自动循环（`DeepDraftCoordinator`：诊断 → 修订 → 复评，带三类退出条件和单元测试）、待复核人工确认状态机、`agent_runs`/`agent_steps` 轨迹持久化、双记忆闭环（作者雷区 + 编辑偏好，归纳自动、生效必须人工确认）、词法检索增强和北极星度量（发表编辑比例）。按 Anthropic 对 agent 系统的分类，这是标准的 **workflow 形态（prompt chaining + evaluator-optimizer + routing）**，不是模型驱动控制流的 **agent 形态**——没有工具调用循环、没有条件分支由模型裁决、advisor 给出的 execution_plan 不被执行。18.12 明确声明过不引入 agent runtime，这个边界本身是对的；问题在于有三处组件顶着"代理"的名字，实际是直通管道（见 22.2）。

**问题二：对写作质量有明显提高吗？——机制在，证据不在；且有四处实现缺陷正在主动抵消收益。**

从代码只能确认"为质量提升修了路"，不能确认"车跑起来了"：全系统没有任何先行评测（eval），北极星指标（20.1 零改动/轻改动发表率）虽已落地但属滞后指标，需要数月发布数据才有统计意义；而 DeepDraft 循环的驱动信号是**同模型、同温度（0.75）的自评分**，第 18.1 章自己的实测数据（4 轮诊断 72→72→72→75）已经说明这个信号分辨率很低。更重要的是，审查发现了四个 P0 级实现缺陷（22.3），其中"全量语料库序列化进 prompt"会让代理式初稿**随着使用时间变长而必然劣化直至不可用**——这恰好与"越用越懂作者"的产品承诺相反。诚实的结论是：当前写作质量的提高**不可证明**，且在长文场景（产品核心场景）大概率被这些缺陷压制。

**值得保留的优点**（本章所有建议都不动这些）：descriptor 收敛 + 护栏脚本、待复核状态机（`pendingDraftReview` 阻塞保存）、防空转提示、记忆闭环的"归纳自动 + 生效人工确认"约束、发表前终审的"模型找引文 + 本地精确比对"分工、依赖注入后补上的编排层状态机测试（`WorkshopStoreTests` 9 条）。这些是同类单人项目里少见的正确设计。

### 22.1 Harness 组件盘点（证据表）

| 组件 | 状态 | 证据 | 评价 |
| --- | --- | --- | --- |
| 声明式工作流 + 执行引擎 | ✅ | `WorkflowEngine.swift`、`NativeWorkflowCatalog.swift`（17 个 descriptor） | R2 完成，护栏防回潮 |
| 四步初稿管线 | ✅ | `AgentDraftCoordinator.swift` | 固定顺序，无条件分支（见 22.2.1） |
| 诊断-修订自动循环 | ✅ | `DeepDraftCoordinator.swift`，3 条专项测试 | 骨架正确，判据有缺陷（22.3.4、22.4.3） |
| 质量门 | ⚠️ | `AgentDraftQualityGate.swift` | 只验字段非空，不验内容质量（22.2.2） |
| 生成后自检 | ✅ | `draftSelfCheck` 工作流 + 编辑器高亮 | 轻量、定位合理 |
| 待复核 HITL 状态机 | ✅ | `finalizeGeneratedDraft` → `pendingDraftReview`，未确认阻塞保存 | 产品级正确 |
| 轨迹持久化 | ✅ | `agent_runs`/`agent_steps`，全部工作流走 `recordAgentRun` | 可复盘 |
| 检索增强（RAG） | ⚠️ | `FragmentRetriever.swift`（字符 bigram Jaccard + 关键词） | 词法版，无停用词/权重，无 embedding |
| 记忆闭环 | ✅ | 雷区归纳、编辑偏好归纳，确认后注入 prompt | 约束设计正确 |
| 北极星度量 | ✅ | `edit_records` + `PublishingMetricsRecorder` | 滞后指标，缺先行评测（22.4） |
| 按工作流模型路由 | ⚠️ | `ModelConfig.workflowOverrides` + 网关解析 | 机制在，无默认种子，UI 是裸 JSON 编辑框 |
| 流式输出 | ❌ | `ModelGateway.stream` 仅有抛错 stub，全库无调用方 | 19.3.5 未实施 |
| 结构化输出保障 / 解析重试 | ❌ | `AIWorkflowRunner` 失败一次即 fallback | 见 22.3.3 |
| 写作质量评测集 | ❌ | 全库无 eval 相关代码 | 见 22.4 |
| 工具调用 / 动态规划 / 多 agent | ❌（有意） | 18.12 产品边界 | 边界正确，不建议改变 |

### 22.2 "代理"名不副实的三处（设计层缺陷）

#### 22.2.1 论点检查的裁决从未被消费

`ArgumentCheckResult.ready_to_draft` 与 `missing_evidence` 在全部源码中只有模型定义（`WorkshopModels.swift:609`）和 prompt 构造两处出现，**没有任何控制流读取它们**。`AgentDraftCoordinator` 拿到论点检查结果后无条件进入分段成稿——检查结论只是下一步 prompt 里的一段上下文。这意味着管线的"检查步"实际是"注释步"：模型明确说"论点撑不起一篇文章、缺三处关键证据"时，系统的反应和"一切就绪"完全一样。一个配得上 agentic 名字的最小改造是：`ready_to_draft == false` 或 `missing_evidence` 非空时，要么自动做一轮有界的 brief 修订（最多 1 次，防循环），要么停下来把缺口列给作者补素材（与 5.1"AI 不替代作者"一致，且素材箱本来就是为此存在的）。

**实施记录**（2026-07-05，任务 5）：新增 `briefRevision` 工作流；`ready_to_draft == false` 或 `missing_evidence` 非空时自动执行一轮（上限一轮）brief 修订并作为独立步骤记入代理轨迹；`unresolved_gaps` 透传至待复核卡片，质量门新增"素材缺口"检查项。

#### 22.2.2 质量门只验"有没有"，不验"好不好"

`AgentDraftQualityGateEvaluator` 的五项检查全部是结构性非空判断：brief 三字段是否填了、修订指令是否存在、分段自检是否 ≥2 条、自我批评是否 ≥1 条、自检是否返回。一份每个字段都填了套话的劣质产出可以全绿通过。质量门要有约束力，至少要加入本地可计算的语义信号：实际段落数与 `structure_plan` 计划段数的偏差、正文长度与计划的偏差、结尾套话模式扫描、雷区特征词扫描。这些都不需要额外模型调用。

**实施记录**（2026-07-05，任务 6）：质量门新增三项本地语义检查——结构偏差（实际段落数 vs `structure_plan` 计划段数交叉比对）、长度完整性与疑似截断（结尾非句末标点）、结尾套话与雷区特征扫描；全部纯函数实现、零模型调用，detail 附具体数字或命中片段。

#### 22.2.3 "智能下一步"的执行计划不被执行

`WritingAdvisorResult.execution_plan` 持久化后仅作展示，推荐动作仍是作者逐个点按钮。作为产品边界这可以接受（作者保留控制权），但 18.12.1 称之为"代理调度器"名过其实——它是一个带结构化理由的推荐器。文档表述应降级，或者（更有价值的方向）允许作者一键"按计划执行"：把 `suggested_actions` 里已经约束好的动作 id 序列交给现有的 `performAdvisorAction` 顺序执行，每步产物仍走待复核。机制全部现成，只缺一个循环。

**实施记录**：未实施（P2，未列入本轮 10 个任务），保留为后续候选。

### 22.3 P0 实现缺陷（直接压制质量与可用性，建议最先修）

#### 22.3.1 全量语料库被序列化进 prompt（最严重，会随使用劣化直至不可用）

证据链：`quickDraft` 把 `rebuildFragments()` 返回的**整库片段**（全部素材 + 全部已发布/已归档文章，每 320 字一片，每片带 24 个关键词）赋给 `context.fragment_corpus`（`WorkshopStore.swift:930`）；`ContextPackage` 是自动合成的 `Codable`，没有排除任何字段（`WorkshopModels.swift:733`）；而 `writingBrief`、`argumentCheck`、`draftCritique` 三个 prompt 都内嵌完整的 `contextJSON(context)`（`NativePrompts.swift:24、69、168`）。

后果：每次"代理式初稿"，整个个人语料库被 pretty-print 成 JSON 塞进 4 步中的 3 步。按日更节奏估算：30 篇存量 ≈ 每次调用多出数万 token（成本、延迟、注意力稀释三重损失）；一年存量（300+ 篇 ≈ 数千片段）直接超出 128K 上下文窗口 → 每步 HTTP 400 → 整条管线永久退化为本地模板 fallback。**写得越多，旗舰功能越不可用**，且故障形态（"已使用本地模拟稿"）不会提示真实原因。

修复方向：`fragment_corpus`、`section_fragment_contexts`、`retrieved_fragments` 不参与 prompt 编码（自定义 `CodingKeys` 排除，或拆一个专供 prompt 的 `PromptContext` 投影）；语料只经 `FragmentRetriever` 检索后按段注入——现有 `sectionFragmentsBlock` 已经是正确姿势，问题只在"整库也顺带进去了"。

验收：任一 prompt 文本中不再出现整库片段；`ai_calls.input_summary` 对应各步的输入长度与库规模无关；用 100 篇模拟文章的库跑代理式初稿，全步成功。

**实施记录**（2026-07-05，任务 1）：`ContextPackage` 改为自定义 `CodingKeys`，`fragment_corpus`、`section_fragment_contexts`、`retrieved_fragments` 不再参与 Codable 编码、仅供内存中直接读取；单元测试断言编码后 JSON 不含片段正文且长度与片段数量无关。

#### 22.3.2 长输出无保障：max_tokens 缺失 + 非流式 + 90 秒默认超时

证据：`ChatCompletionRequest` 没有 `max_tokens` 字段（`ModelGateway.swift:81-86`），目前连配置通道都不存在；`stream: false`（`:56`）；默认超时 90 秒（`:9`）。整篇长文装在单个 JSON 字符串字段里返回。

后果：长文恰好是产品核心场景，而输出侧完全靠服务商默认值——输出被默认 max_tokens 截断时 JSON 必然解析失败 → 整步 fallback；生成慢于 90 秒时超时 → 整步 fallback。系统性地惩罚"最长、最完整"的那次生成，这与 18.1 观察到的"长文中段变空、疑似截断"直接相关。

修复方向：`ModelRouteConfig` 增加 `maxTokens`；为 draft/polish/深度修订类工作流设置默认 max_tokens 与 ≥240 秒超时；实现 `ModelGateway.stream`（接口位早已留好，19.3.5）并让 draft 类工作流优先走流式——流式同时解决超时、截断可见性和等待体验三个问题。

**实施记录**（2026-07-05，任务 2 + 任务 9）：`ModelRouteConfig` 已加 `maxTokens`；`AIWorkflowKind.defaultParameters` 提供代码级默认——判别类 0.2 / 4096 / 120s，生成类 0.75 / 8192 / 240s，其余 0.75 / 4096 / 120s；参数优先级为用户 `workflowOverrides` > 工作流默认 > 全局默认。流式已实现：`OpenAICompatibleModelGateway.stream(_:)` + `AIWorkflowRunner` 的 `onPartialOutput` 增量回调，生成大纲、大纲成稿、全文润色、局部改写执行中显示流式进度（详见 19.3.5 实施记录）。

#### 22.3.3 解析失败无重试，fallback 产物污染下游步骤

证据：`AIWorkflowRunner` 任何错误（网络、HTTP、JSON 解析）一次即降级为本地 fallback（`AIWorkflowRunner.swift:41-60`），没有重试；`AgentDraftCoordinator` 对中间步失败不熔断，继续把 `NativeFallbacks` 的模板产物作为下一步输入（`AgentDraftCoordinator.swift:19-63`）。

后果：例如分段成稿一步因输出截断解析失败，"自我批评与整合"会认真地批评并整合一份**本地模板稿**，最终产出一篇模板腔的"初稿"进入待复核——状态标着 fallback，但正文看起来像回事，作者可能在不知情下基于它继续改。fallback 的正确角色是"无 API Key 时演示流程"，不是"多步管线的中间输入"。

修复方向：(a) `invalidJSON`/`emptyContent` 增加一次重试，把解析错误摘要附回给模型——这是结构化输出最廉价的可靠性手段，成本上限 +1 次调用；服务商支持时按工作流开启 `response_format: json_object`。(b) 协调器语义改为熔断：关键步失败即停止管线，携带已完成步骤的 trace 和最后一份真实产物进入待复核，fallback 产物永不作为后续模型步骤的输入。

**实施记录**（2026-07-05，任务 3）：`AIWorkflowRunner` 对解析类错误（invalidJSON / emptyContent / DecodingError）附带错误反馈重试一次，重试与否记入 `ai_calls` 摘要；`AgentDraftCoordinator` 每步经 `circuitBreak` 判定，非"未配置 API Key 演示模式"的失败立即熔断且不调用后续步骤，`quickDraft` 熔断时不产生待复核版本、不改动正文；`DeepDraftCoordinator` 诊断/修订步失败即停轮并以当前最好版本收尾，fallback 稿不再写回正文。均有单元测试覆盖（含 missingAPIKey 演示路径回归）。

#### 22.3.4 判别类调用与生成类调用共用 0.75 温度

证据：`ModelGatewayRequest.temperature` 默认 0.75（`ModelGateway.swift:8`），写作诊断、候选评委、发表前终审、生成后自检全部按此采样（除非作者手写 overrides JSON）。

后果：判别任务被高温采样注入噪声——DeepDraft 的收敛判据是"连续两轮提升 < 3 分"，而同一稿件两次 0.75 温度的评分波动很容易超过 3 分，收敛判定近似掷骰子；候选评委的排序同样不稳定，且候选按固定顺序呈现，位置偏置无对冲。

修复方向：为判别类工作流（writingReview、candidateJudge、prePublishAudit、draftSelfCheck、pitfallSummary、editPreferenceSummary）种子化默认低温（0.0–0.3）的 `workflowOverrides`，写入 settings 默认值而不是等作者手写 JSON；候选评委呈现顺序随机化，并在 trace 里记录呈现顺序。

**实施记录**（2026-07-05，任务 2 + 任务 4）：实现方式与提案略有差异——低温默认没有种子进 settings，而是做成代码级默认（`AIWorkflowKind.defaultParameters`，判别类含 writingAdvisor、readerPerspective 一并降到 0.2），用户 overrides 仍然优先，效果等价且免去数据迁移。候选评委呈现顺序已随机化（随机源可注入、固定种子可复现），呈现顺序记入该步 `input_summary`。

### 22.4 写作质量"有无提高"的证据缺口

1. **滞后指标已就位，先行指标为零。** `edit_records` + 零改动/轻改动率是对的，但它按月出数、受选题难度和作者状态干扰，无法归因到任何一次改造。当前仓库没有任何评测代码——第 18 章、20 章两轮"质量改造"的验收全部依赖人工抽检和单元测试（测的是状态机，不是文本质量）。
2. **建议建立最小写作评测集（本章最高杠杆项）。** 固定 10–20 个真实输入（历史想法 + 历史初稿），每次改动前后对照跑三条管线（直接成稿 / 代理式初稿 / 深度成稿），用低温评审 prompt 按既有诊断维度打分 + 作者盲评抽检，结果写入 `agent_runs` 同源的评测表。没有这一步，"代理链路是否值回 4–11 次调用的成本"永远无法回答，第 20 章北极星也无法归因。实现量级：一个评测 runner + 一张表 + 一个对比视图，全部复用现有 descriptor 基建。
3. **自评自改的收敛判据应换主信号。** `resolved_from_last` 机制是好的，但循环的主判据仍是同模型自评分。建议：以"上一轮高/中 issue 的核销率"为主判据（数据结构已存在），分数降为辅助显示；终评轮通过既有 `workflowOverrides` 路由到更强模型，实现"生成-评审分离"的最小版本。另注意 `pitfallHits` 的正文直配检查（`DeepDraftCoordinator.swift:227`）近乎无效——雷区描述是建议句式（如"少用金句收束"），不会字面出现在正文里，实际只有 issue 文本匹配分支在工作；应让诊断 prompt 显式输出 `pitfall_hits` 字段，或为每条雷区维护特征词表。

**实施记录**（2026-07-05，任务 7 + 任务 8）：深度循环主判据改为"上一轮高/中 issue 核销率"——核销率 ≥0.8 且无新增高严重度且未命中雷区即停止，连续两轮核销率 <0.3 判定空转停止；`overall_score` 降为迭代摘要展示信息，不再参与停止判定。诊断 prompt 已显式输出 `pitfall_hits`（原样抄写雷区描述），`DeepDraftCoordinator` 优先消费模型判定、保留 issue 文本匹配兜底、删除正文直配分支。评测基建落地：SwiftPM 新增 `CreativeWorkshopEval` 可执行目标（复用 `CreativeWorkshopCore`，不被主 App 依赖），`evals/cases/` 用例 + 独立结果库 + Markdown 对比报告，运行方式见 README；无 API Key 时明确报错退出。

### 22.5 改进优先级汇总

| 优先级 | 项 | 一句话理由 | 量级 |
| --- | --- | --- | --- |
| P0 | 22.3.1 语料泄漏 | 旗舰功能随使用必然劣化，修复立竿见影 | 半天 |
| P0 | 22.3.2 max_tokens/超时/流式 | 长文场景的截断与超时是当前最大质量泄漏点 | 1–2 天（流式单列） |
| P0 | 22.3.3 解析重试 + 管线熔断 | 消除模板稿污染，一次重试换一个数量级的解析可靠性 | 1 天 |
| P0 | 22.3.4 判别低温 + 默认路由种子 | 让循环判据和评委排序从"掷骰子"变成可信号 | 半天 |
| P1 | 22.2.1 消费论点检查裁决 | 管线从"注释式检查"变成真正的门 | 1 天 |
| P1 | 22.2.2 质量门语义化 | 零模型成本提高门的约束力 | 1 天 |
| P1 | 22.4.2 最小评测集 | 回答本章问题二的唯一严肃方式 | 2–3 天 |
| P1 | 检索升级：停用词 + IDF 加权 + 命中率入 `agent_runs` | 词法检索的免费精度提升；embedding 版继续后置 | 1–2 天 |
| P2 | 22.2.3 计划一键顺序执行 | 现成机制拼装，advisor 从推荐器升级为半自动调度 | 1–2 天 |
| P2 | 文档漂移修正（22.6） | 让 PRD 恢复"可信基线"地位 | 半天 |

### 22.6 文档与代码漂移清单

本次审查发现 PRD 状态标注已明显落后于代码，下一轮任何审查都会被迫重新读码反推真相，建议回填：

1. 第 20 章标"提案，尚未实施"，实际 20.2（`DeepDraftCoordinator`）、20.3 词法版（`FragmentRetriever` + `fragments` 表）、20.4（`edit_records` + `learned_preferences`）、20.5（`PrePublishAuditCoordinator` + 本地引文核对）、20.6（多候选评委 + `workflowOverrides` 路由）均已落地，应按 18 章惯例逐节回填实施记录。
2. 第 21 章 R1–R4 已完成（依赖注入 + 测试、descriptor/引擎、ContextPackage 注入、`ModelGateway` 协议），R5 进行中（Store 2599 行，护栏警戒线 2600）；21.5 护栏已落为 `script/architecture_guard.sh`。
3. `PRD_完成度审计.md` 称"流式输出、模型路由"不在范围——模型路由已实现，流式仍未实现，表述应更新。

**实施记录**（2026-07-05，任务 10）：第 18/20/21 章与 `PRD_完成度审计.md` 均已回填，本节所列漂移已清除；流式随任务 9 落地后，相关表述（18 章状态行、20.6 实施记录、19.3.5、完成度审计）已二次更新。

### 22.7 明确不建议做的事（防过度工程）

1. **不引入 agent 框架、MCP、工具调用循环、多 agent 协作。** 18.12 的边界依然正确：当前的短板是管线正确性、输出可靠性和质量证据，不是"自主性不足"。写作域的"工具"（检索、诊断、改写、终审）已经枚举齐全并各有工作流。
2. **不推倒 `DeepDraftCoordinator` 重写。** 循环骨架、退出条件框架和三条测试是对的，需要换的只是判据信号（22.4.3）和采样温度（22.3.4）。
3. **不在本轮做 embedding 检索。** 词法版还有免费的精度空间（停用词、IDF），且 22.3.1 修复后检索质量才有干净的观测环境。
4. **不做自动发布。** 待复核与作者定稿权是全系统最有价值的产品约束，任何"零改动"目标都不得绕过它（与 20.8 最后一条一致）。

### 22.8 建议执行顺序

1. 22.3.1 语料泄漏修复（半天内完成，先堵住随使用劣化的洞）。
2. 22.3.4 判别低温 + 默认路由种子、22.3.3 解析重试与熔断（可信号、可靠性）。
3. 22.3.2 max_tokens 与超时默认值；流式实现单独排期（与 19.3.5 合并）。
4. 22.4.2 最小评测集——在做任何进一步"质量改造"之前先有尺子，用它验证 1–3 的效果。
5. 22.2.1 / 22.2.2 让检查步和质量门真正生效。
6. P2 项与文档回填按余力推进。



## 23. Agentic Harness 演进提案：从固定管线到有界代理循环（待审查）

状态：已实施（评测驱动的条件项除外；2026-07-07 回填）。本章 2026-07-05 作为提案提出，经作者审查后拆解为任务 11–19（见 `创作工坊-23章改进-执行提示词.md`）：任务 11–16 已完成并经核验（全量测试通过、`architecture_guard.sh` 通过）；任务 17（write_section）为证据门条件任务，首判"数据不足"未实施，待第二轮评测复判；任务 18（调度偏好）待代理会话样本 ≥5 后启动；任务 19 即本次回填。各节末尾附实施记录，正文保留提案时点的原始表述。

### 23.0 定位：向 agentic 演进到底是在改什么

22.2.1 的改造（`ready_to_draft == false` 或 `missing_evidence` 非空时，自动做一轮有界 brief 修订）本质上是**第一个由模型裁决的条件分支**：模型给出判断，代码消费判断并改变控制流。一个 agentic harness 就是把这种"模型建议 → 护栏裁决 → 执行 → 验证"的模式，从一个硬编码特例推广成一个通用循环。workflow 与 agent 的分界从来不是"有没有多步"，而是**下一步由谁决定**：

- 现在（L1）：每一步由 Swift 代码决定——固定管线（代理式初稿五步）+ 固定退出条件的循环（深度成稿核销率判据）。
- 目标（L2）：**下一步由模型在封闭动作空间内选择，护栏负责预算、验证、熔断和终审。**

必须先说清不变量：向 agentic 演进**不是**扩大 AI 对作者的自治，而是扩大 AI 在"两次作者检查点之间"对过程的自治。三条底线继承自 5.1 / 18.2.1 / 22.7，本章任何设计不得触碰：

1. 一切代理产物仍进入 `pendingDraftReview` 待复核，作者是唯一定稿人。
2. 动作空间封闭、可枚举——不做 MCP、外部工具、命令执行、多 agent。
3. 每升一级自治，必须先过第 22 章建立的评测放行门（23.4）；评测不达标就不设为默认。

### 23.1 现状盘点：器官齐全，缺一个决策环

| Harness 器官 | 现有组件 | 状态 |
| --- | --- | --- |
| 工具箱 | 17+ 个 `WorkflowDescriptor`（`NativeWorkflowCatalog`） | ✅ 类型化、可组合、护栏防绕过 |
| 观察 | `ContextPackage` + `WritingContextBuilder` + 质量门/自检/诊断结果 | ⚠️ 信号分散，未汇成单一"会话状态"（23.7） |
| 计划 | `WritingAdvisorResult.execution_plan` | ⚠️ 只展示不执行（22.2.3 遗留） |
| 执行 | `WorkflowEngine` + 各协调器 | ✅ 已含熔断、解析重试、流式 |
| 验证 | `AgentDraftQualityGateEvaluator`（已语义化）+ `draftSelfCheck` + 本地引文核对 | ⚠️ 结果只给人看，不回流进任何决策（23.7） |
| 记忆 | `known_pitfalls` + `learned_preferences` + `resolved_from_last` | ✅ 归纳自动、生效人工确认 |
| 轨迹 | `agent_runs` / `agent_steps` | ✅ 缺"决策"步类型（23.6） |
| 预算 | 无 | ❌ 目前只有固定轮数上限 |
| **决策环** | **无** | ❌ 本章主体（23.6） |
| 终审门 | `pendingDraftReview` | ✅ 不动 |
| 裁判 | `CreativeWorkshopEval` | ⚠️ 用例仍是占位（23.4 前置） |

结论：不需要新框架、不需要新依赖，几乎不需要新 prompt——需要的是一个**消费现有 descriptor 的调度协调器**，加上预算、观察压缩和决策轨迹。

### 23.2 自治分级与本阶段目标

| 级别 | 名称 | 下一步由谁决定 | 对应 |
| --- | --- | --- | --- |
| L0 | 单发工具 | 作者点按钮 | 选题/大纲/润色等单步工作流 |
| L1 | 固定管线与循环 | Swift 代码（含消费模型裁决的硬编码分支） | 代理式初稿、深度成稿（现状） |
| L1.5 | 半自动调度 | 模型出静态计划，作者一键批准，代码顺序执行 | 22.2.3 落实（23.5） |
| L2 | 有界代理循环 | 模型每步在封闭动作空间选择，护栏裁决 | 本章核心（23.6），先进"实验室"开关 |
| L3 | 开放代理 | 模型自定义工具与流程 | **明确不做**（23.9） |

### 23.3 护栏继承：把第 22 章的教训固化为五条设计律

第 22 章修掉的每个 P0 缺陷，都对应决策环时代会被放大的风险。固化为设计律，23.6 的实现必须逐条对照：

1. **语料不进决策上下文，只进检索结果**——观察必须压缩（一行式历史、摘要化信号），严禁把整库素材或全文塞进决策 prompt（22.3.1 教训）。
2. **fallback 产物不进下游**——决策环中任何一步失败即按熔断语义处理，模板产物不得成为下一步观察（22.3.3 教训）。
3. **判别低温、生成高温**——决策步是判别类调用，走 0.2 默认温度与小 max_tokens（22.3.4 教训）。
4. **每步可验证、可追溯**——每个动作后跑本地验证器，决策 JSON 原文入轨迹（22.2.2 的正面运用）。
5. **一切自治在待复核之内**——`finish` 永远合法，预算耗尽必交付当前最好版本，不空手（12 章 / 20.2.5 要求）。

### 23.4 P0 前置：真实评测用例与放行门（半天，其余各节的闸门）

`evals/cases/` 目前是 3 个占位用例。本章所有升级"是否值得默认开启"都由评测回答，因此第一步是：

1. 作者替换/补充 10–20 个真实用例（历史想法 + 历史初稿，两类 kind 均衡），敏感内容可脱敏。
2. 定义放行门并写进 eval 报告模板：**L2 转为默认入口，当且仅当**在固定用例集上 (a) rubric 总分不低于深度成稿管线；(b) 平均模型调用次数 ≤ 深度成稿的 1.5 倍；(c) fallback/熔断率不高于深度成稿。
3. 本章每完成一个任务重跑一轮留底（`evals/reports/` 已支持与上一次对比）。

验收：真实用例入库；报告含三管线对照与放行门三项自动判定。

**实施记录**（任务 11，2026-07-06 起）：用例结构校验与可执行错误信息、`evals/cases/README.md`、放行门三项判定（`ReportGenerator` + `ReleaseGate`）落地。真实用例 2026-07-06 入库 6 个（三组"一鱼两吃"配对），2026-07-07 扩充至 24 个（11 组配对 + 2 个纯 idea，draft 11 / idea 13，含十二钗系列八篇与古龙风格练习）。首轮全量评测 2026-07-07 完成（`evals/reports/2026-07-07T18-29-23Z.md`），随即完成评测仪器修缮：评分锚点模板（eval 专属，不动 App 内写作教练 prompt）、验证信号列接内容级本地检查、agentic 会话轨迹入报告、无分数自动重评一次。注意：换锚点评分后第二轮起为新基线，与首轮分数不可直接比。

### 23.5 P1：半自动调度——先把"计划"变成"可批准的计划"（落实 22.2.3，L1.5）

改造：智能下一步产出 `execution_plan`/`suggested_actions` 后，卡片增加"按计划执行"按钮。作者批准 → 代码按序执行动作序列（复用 `performAdvisorAction` 的动作映射，逐步走既有工作流）；每步完成后更新进度；生成类产物照常进入待复核，出现 pending 时序列暂停，等作者确认或放弃后再继续。整个执行序列作为一条 `agent_runs` 记录，逐步落 `agent_steps`。

为什么先做它：这是 L1.5——计划是静态的（不重规划），但作者第一次获得"批准一次、系统连走多步"的体验；同时为 23.6 攒下多步会话的 UI 与轨迹形态，风险几乎为零。

验收标准：

1. 计划执行中可随时取消，已完成步骤的产物保留。
2. 中途某步失败，序列停止并给出失败原因，不影响已完成产物。
3. pending 待复核未处理时，序列不得越过它继续执行。
4. 全程一条 agent_run 可复盘。

**实施记录**（任务 12）：编排落 `AdvisorPlanRunner.swift`（Core），Store 只留状态绑定与入口（`WorkshopStore+AdvisorPlan.swift`）；可执行动作子集按提案实现，rewrite_selection_* 与 save_article 跳过并注明；生成步产生待复核即暂停，作者确认后自动续行、放弃则整个序列停止；序列以 `agent_runs.session_kind = "plan_execution"` 留痕，逐步落 `agent_steps`。

### 23.6 P1：有界代理循环 `WritingAgentCoordinator`（L2，本章核心）

一句话：把"深度成稿"的**固定循环**升级为"模型观察 → 选动作 → 护栏执行 → 验证回流"的**决策循环**，全部复用既有 descriptor。

#### 23.6.1 会话状态与观察压缩

新增 `AgentSessionState`（内存结构）：写作目标（想法/方向/选题）、当前稿件度量（阶段、字数、大纲有无）、最新验证信号（质量门各项、最近诊断评分与高/中问题数、pitfall_hits、自检标记数）、动作历史（每条一行："动作 → 结果一句话 → 信号变化"）、剩余预算。观察规则：正文只给首尾节选，完整产物只入轨迹、不入决策上下文（设计律 1）。

#### 23.6.2 动作空间（封闭枚举，前置条件由护栏强制）

`generate_outline`、`draft_from_outline`、`agent_quick_draft`、`writing_review`、`improve_from_review`（前置：存在诊断且有未解决问题）、`polish_natural`、`polish_tighten`、`search_materials{query}`（本地检索，见 23.8）、`ask_author{questions}`（每会话至多 1 次）、`finish`。模型选择了前置不满足的动作 → 给一次纠正观察让它重选，再违规 → 安全停机交付。

#### 23.6.3 决策工作流 `agentDecision`（判别类、低温、小输出，本章唯一新增 prompt）

模板照常进 `prompt_templates` 可编辑，并接入 `appendAgentDiscipline`（新增 decision 模式聚焦）。默认文案：

```text
你是我的中文写作代理调度器。你的职责不是写作，而是根据当前会话状态，
决定下一步执行哪一个动作，或者停下来。

【写作目标】
{goal}

【当前稿件状态】
{阶段 / 字数 / 大纲有无 / 最近诊断摘要（评分、高中问题数、命中雷区）/ 质量门摘要 / 自检摘要}

【已执行动作历史】
{按序每行：动作 → 一句话结果 → 验证信号变化}

【剩余预算】
{剩余模型调用次数；本会话已用次数}

【可用动作】（只能从中选择，且必须满足括号内前置条件）
{由护栏按当前状态生成的动作清单及说明}

决策纪律：
1. 每次只选一个动作；优先解决验证信号里的高严重度问题
2. 同一动作连续使用不得超过 2 次；上一动作没有改善验证信号时，必须换路径或选 ask_author / finish
3. 预算剩余不足 3 次时，只允许 writing_review、ask_author 或 finish
4. 缺证据时用 search_materials 或 ask_author，不得让生成动作编造经历
5. 不确定时倾向 finish——把判断交还作者永远是合法选择

请只输出 JSON，不要输出 Markdown 代码块：
{"action":"动作 id","arguments":{"query":"仅 search_materials / ask_author 需要"},
 "reason":"选择这一步的原因","expected_gain":"预计改善哪个验证信号","stop":false}
```

#### 23.6.4 预算与熔断

1. 每会话模型调用上限默认 12（决策步计入）；剩余 ≤2 时动作空间收缩为 {writing_review, ask_author, finish}（prompt 纪律 + 护栏双重强制）。
2. 同一动作连续 >2 次 → 强制停机；动作执行后状态哈希（标题 + 正文 + 验证信号摘要）不变 → 记一次"空转"，累计两次空转 → 停机交付。
3. 决策 JSON 非法或动作越界 → 复用任务 3 的解析重试一次 → 仍失败 → 停机交付当前最好版本。
4. 任何一步触发 22.3.3 熔断语义 → 会话结束，携带完整轨迹进待复核。`missingAPIKey` 时代理会话直接不可用并提示配置 Key——决策环没有"假演示"的意义，这是与既有演示模式的有意区别。

#### 23.6.5 交付与 UI

`finish` 或任何停机 → 当前最好版本进 `pendingDraftReview`，卡片新增"会话摘要"：共 N 步、每步动作与理由一行、验证信号首尾对比、停止原因。`ask_author` → 产出"代理提问"卡：具体缺口清单（缺哪段素材、哪个判断需要作者拍板），作者补完后可一键继续同一会话（预算继承）。执行中沿用既有流式状态展示，随时可取消。

#### 23.6.6 灰度：实验室开关

第一版藏在设置"实验室"开关后，默认关闭，"深度成稿"保持默认入口；通过 23.4 放行门后才对调。

验收标准：

1. 假 executor 确定性测试覆盖：预算耗尽必交付、连续重复强制停止、空转检测、前置违规纠正、决策 JSON 非法停机、ask_author 暂停与续跑。
2. 每个决策步以 `step_type = "decision"` 落 `agent_steps`，决策 JSON 原文可查。
3. agentic 管线进入 eval 对照，放行门三项判定自动出现在报告中。
4. 实验室开关关闭时，系统行为与本章实施前完全一致。

**实施记录**（任务 14 + 15）：`WritingAgentCoordinator.swift` 落地——会话在本地状态上直接消费 workflow descriptor，中间产物不进待复核、仅终点交付（避免 pending 死锁）；预算走 settings 键 `agent_call_budget`（默认 12），决策步计入；决策以 `step_type = "decision"` + `decision_json` 落 `agent_steps`；`ask_author` 每会话至多一次、可续跑；`missingAPIKey` 时会话入口直接不可用（不做假演示）。UI：设置页"实验室"开关（`agent_lab_enabled`，默认关）、执行进度、待复核卡会话摘要、代理提问卡。

**放行门记录（23.6.6）**：首轮评测（2026-07-07，6 用例，旧评分尺）三项判定——rubric 均分 agentic 72.33 < deep 75.00（**不通过**）；平均调用次数 11.67 ≤ 1.5 × 10.00（通过）；熔断率均 0%（通过）→ **放行门不通过，L2 维持实验室开关内，不转默认**。附注：首轮 agentic 六场全部跑满或接近预算、从不提前 finish，会话轨迹已随仪器修缮接入报告可供诊断；仪器修缮后的第二轮评测（24 用例）进行中，达标后再复议转默认。

### 23.7 P1：验证信号统一为 `VerificationReport`（决策环的眼睛）

质量门、自检、雷区命中、（发布路径的）终审目前各自为政，决策环需要统一观察。抽 `VerificationReport`：来源标注 + 分级条目 + 一行摘要，三个消费方——决策上下文（压缩为 ≤6 行）、待复核卡片（现有 UI 改读新结构，展示不变形）、eval 报告（rubric 之外的客观信号列）。纯重组、不新增检查。另一条诚实性规则：存在高严重度未处理条目时模型仍可选 `finish`，但护栏要求其在 reason 里显式说明理由并入轨迹——允许交付，不允许假装全绿。

验收：三个消费方读同一结构；决策 prompt 中验证信号不超过 6 行。

**实施记录**（任务 13 + 仪器修缮）：`VerificationReport` 落地（gate/自检/雷区/终审四源统一，`summaryLine` + `compactLines(limit:)`），待复核卡片与决策上下文已接入。eval 报告的验证信号列在首轮恒为空（管线产物未过任何检查即送评分），已随仪器修缮改为对所有管线最终产物统一跑内容级本地检查（完整性/疑似截断 + 雷区套话扫描，零模型调用）。

### 23.8 P2：检索动作化、分节写作动作化与调度记忆

1. **`search_materials` 动作**：检索从"代码在固定时机注入"升级为"模型发现证据缺口时主动调用"，query 由模型给出，top-3 片段进入观察并计入引用轨迹；同批落地第 22 章遗留的检索升级（停用词 + IDF 加权 + 命中率入 `agent_runs`）。本地零网络——这是唯一"像工具"的新增，但仍在封闭动作空间内。
2. **`write_section{index}` 动作**（可选，评测驱动）：把分段成稿拆为逐节动作，每节即时过验证器，直接攻击"长文中段变空"；仅当 23.4 评测显示"整篇一次生成"仍是主要失分点时才做。
3. **调度偏好记忆**：会话结束后轻量复盘（哪类动作序列对这位作者收益高、哪类动作总在浪费预算）→ 候选调度偏好 → 人工确认后注入 `agentDecision` prompt。机制完全复用雷区/编辑偏好的"归纳自动、生效人工确认"闭环。

**实施记录**：
1. `search_materials`（任务 16）：已实施——动作接入会话与评测（本地检索不计入调用预算，报告单列 searchCount），`FragmentRetriever` 升级为停用词过滤 + IDF 加权重叠评分，命中记录入轨迹。
2. `write_section`（任务 17，条件任务）：**未实施**——2026-07-06 首次执行按证据门停止（当时无任何评测报告）；2026-07-07 首轮报告亦不支持实施（唯一一次截断系网络超时所致、验证信号列当时缺失，无证据显示"整篇一次生成"是主要失分点）。待仪器修缮后的第二轮评测出报告复判。
3. 调度偏好记忆（任务 18）：**未实施**，待真实代理会话样本 ≥5 条后启动。

### 23.9 明确不做（L3 边界，重申并细化）

1. 不做 MCP、外部工具、命令执行、联网检索；不做多 agent 辩论或角色扮演编队。
2. 不做后台无人值守会话：会话必须由作者当次发起、全程可取消。
3. 不做自动发布：`ask_author` 与 `finish` 是自治的天花板。
4. 动作空间的每一次扩充都必须走"提案 → 评测 → 放行"，禁止顺手加动作。
5. L3 只有在 L2 的评测证明存在其解决不了的质量天花板时，才重新讨论。

### 23.10 数据模型与模块变更汇总

| 变更 | 内容 | 用途 |
| --- | --- | --- |
| `agent_steps.step_type` / `decision_json` | 新列：decision / action / verification；决策原文 | 23.6 决策可审计（历史行默认 action） |
| `agent_runs.session_kind` / `budget_summary` | 新列：plan_execution / agent_session；预算用量摘要 | 23.5 / 23.6 |
| settings：`agent_call_budget` 等 | 新键（默认 12） | 23.6 预算 |
| `WritingAgentCoordinator.swift` | 新协调器，复用 `WorkflowEngine` 与全部既有 descriptor | 23.6 |
| `agentDecision` prompt + 模板种子 | 本章唯一新增 prompt | 23.6 |
| `VerificationReport` | 新内存结构（纯重组） | 23.7 |
| eval pipeline `agentic` + 放行门判定 | eval runner 扩展 | 23.4 |

schema 变更走 `PRAGMA user_version` 迁移。

### 23.11 风险与应对

| 风险 | 应对 |
| --- | --- |
| 决策环乒乓/空转烧预算 | 重复上限 + 状态哈希空转检测 + 硬预算 + `finish` 永远合法 |
| 调用成本高于深度成稿 | 决策步为小输入低温调用；放行门 (b) 直接卡 1.5×；实验室开关灰度 |
| 模型调度不如手写启发式 | advisor 既有启发式写入决策纪律作先验；放行门 (a) 不达标不转默认 |
| `ask_author` 滥用打断作者 | 每会话至多 1 次且问题必须具体到缺口；违规按 `finish` 处理 |
| 决策上下文再次膨胀 | 观察压缩规则 + 设计律 1；决策步输入长度入 `ai_calls` 摘要，可监控回归 |
| 新抽象回潮成第二框架 | 只新增 1 个协调器 + 1 个 prompt + 少量新列；`architecture_guard.sh` 加一条：协调器内禁止手写 prompt，动作必须映射到 `NativeWorkflowCatalog` |

### 23.12 建议执行顺序

1. 23.4 真实用例 + 放行门（半天）——先立闸门。
2. 23.5 半自动调度（1–2 天）——最小体验闭环，攒 UI 与轨迹形态。
3. 23.7 `VerificationReport`（1 天）——为决策环备好观察。
4. 23.6 有界代理循环（3–5 天，实验室开关内）——跑 eval 对照。
5. 放行门达标 → L2 转默认；不达标 → 按报告失分点转向 23.8（检索动作化 / `write_section`）再回评。
6. 23.8 调度偏好记忆最后做——它需要会话数据积累。

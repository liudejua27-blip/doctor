# ADR-0003：以规范身体位置作为 2D / 3D 的唯一事实契约

- 状态：**Accepted for design baseline**
- 日期：2026-08-05
- 决策人角色：领域模型负责人、iOS 负责人、人体资产负责人；区域本体仍需解剖/临床内容审核
- 决策范围：iOS 2D、默认 3D、专业 3D、报告、档案和 Agent 工具
- 关联需求：PRD-F01、PRD-F03A、PRD-F03B、PRD-F05、PRD-F06
- 关联验证：T-BODY-001～012、T-CONTRACT-001
- 关联规格：[2D / 3D 身体地图规格](../08_BODY_MAP_2D_3D.md)
- 前置边界：[ADR-0004 iOS 3D 渲染边界](ADR-0004-ios-3d-rendering-boundary.md)、[ADR-0018 BodyAssetManifest 运行时门禁](ADR-0018-body-asset-manifest-runtime-gate.md)
- 机器契约：[BodyLocation JSON Schema](../contracts/body-location.schema.json)、[BodyAssetManifest JSON Schema](../contracts/body-asset-manifest.schema.json)

## 背景

产品允许用户通过以下方式表达身体位置：

- 2D 前/后/侧人体图；
- 默认中性、低细节 3D 人体；
- 专业肌肉、骨骼/关节 3D 人体；
- 搜索和可访问的部位列表；
- 文字、语音或导入资料中的位置描述。

这些视图的几何结构、坐标、LOD、区域颗粒度和生命周期不同。如果每个视图各存一套位置，必然产生：

- 2D 和 3D 标记重复；
- 左右侧或前后表面不一致；
- 更换模型后针点漂移；
- 专业模型实体名被误当成用户事实；
- 报告无法稳定引用历史位置；
- Agent 读取到互相冲突的“事实”；
- 资产版本升级覆盖旧记录。

RehabMate 当前把区域存在数组下标、针点存在 Scene 世界坐标，并用命中三角形首顶点的最近中心分区命名位置。这一设计适合临时演示，不满足跨视图、持久化和长期档案要求。

## 决策

系统采用一个版本化、与渲染引擎无关的 **Canonical `BodyLocation`** 作为位置唯一事实契约。

所有 2D、默认 3D、专业 3D、列表和语音位置先转换成 `BodyLocationCandidate`；只有用户确认后才形成正式 `BodyLocation` 并进入 `BodySignalEvent`。

视图坐标、模型实体和屏幕像素都是证据或渲染锚点，不是独立业务事实。

文字部位搜索/列表是与图形输入等价的广义区域入口：它使用版本化目录的 `region_id`、侧别和适用表面，并以 `source.interaction=body_part_search` 记录选择。除非用户在可视图上明确点选并产生有效 2D/3D 锚点，列表不得以区域几何中心、显示名称或当前 Pin 模式合成 `Point`。

## 规范坐标

采用右手 Canonical Body Space：

- `+Y` 向上；
- `+Z` 为人体前方；
- `+X` 为用户自身右侧；
- 单位为米；
- 根原点由资产 Manifest 固定；
- 左右相对用户身体，不相对观察者或屏幕。

源资产必须在离线流水线或不可变 Manifest 变换到该坐标。不得在每次启动时依赖动态包围盒重新决定方向、身高和原点。

## 位置组成

正式位置至少由四层组成：

1. **语义区域**：`region_id`、左右侧、表面和主观深度；
2. **用户证据**：用户原话、选择路径和来源视图；
3. **几何锚点**：2D、3D 或规范表面锚点；
4. **溯源与置信度**：资产、拓扑、映射和协议版本。

v1 最小字段必须与机器契约一致。Schema 使用 `additionalProperties: false`，不得由客户端自行扩展：

| 字段 | 决策 |
|---|---|
| `marker_id` | 必须；跨视图保持不变的 UUID，也是 v1 位置身份 |
| `region_id` | 必须；稳定本体 ID |
| `ontology_version` | 必须；解释 `region_id` 的本体版本 |
| `laterality` | 必须；`left/right/midline/bilateral/unspecified` |
| `surface` | 必须；`anterior/posterior/medial/lateral/superior/inferior/circumferential/unspecified` |
| `depth` | 必须；`superficial/deep/joint_nearby/unspecified`，仅为用户感觉 |
| `shape` | 必须；`point/area/path` |
| `user_label` | 可选；用户原始位置表达 |
| `anchor_2d` | 2D 来源时必须 |
| `anchor_3d` | 3D 来源时必须 |
| `model_asset` | 有 3D 锚点时必须；资产 ID/版本、变体和坐标约定 |
| `mapping` | 必须；方法、0–1 置信度、用户复核和可选迁移 ID |
| `source` | 必须；交互来源，以及可选 Turn/文档 ID |
| `created_at` | 必须；位置创建时间，事件确认时间属于 `BodySignalEvent` |

协议版本由 JSON Schema `$id` 和 API 版本管理。规范表面图、拓扑、LOD、区域图和迁移算法属于 AssetManifest/MigrationRecord，通过 `model_asset` 和 `mapping.migration_id` 关联，不直接新增到 v1 BodyLocation。

## 2D 锚点决策

2D 不保存屏幕像素。v1 `anchor_2d` 包含：

- `asset_id/asset_version`；
- `view=front/back`；
- 0–1 归一化 `point`、2–256 点的 `path` 或 `region_mask_id` 至少一种。

侧面/局部图可以作为 UI 辅助，但在 Schema 正式升级前不增加未声明字段；规范表面对应、命中版本和边界歧义保存在资产/映射记录。

2D 路径变化不修改旧锚点；通过版本化迁移产生新候选。

列表产生的广义区域使用 `shape=area + region_mask_id`；其目录浏览前/后状态只决定可见选项，不得把当前屏幕或镜头方向猜成新的表面语义。

## 3D 锚点决策

3D 不以世界坐标作为持久化锚点。v1 `anchor_3d` 保存：

- `entity_id`；
- 可选 `mesh_id`；
- `local_position/local_normal`；
- 可选 `triangle_index/barycentric/uv`；
- 独立的 `model_asset` 提供资产 ID/版本、默认或专业变体及 `realitykit_y_up_right_handed` 坐标约定。

拓扑 ID、LOD、规范表面图、区域图和解析器版本保存在该资产的 AssetManifest。同拓扑使用 triangle + barycentric 精确重建；跨拓扑和跨模型优先使用 Manifest 中的规范表面对应。局部点和法线用于回放、交叉验证与兼容，但不能独自承担迁移。

`triangle_index` 与 `barycentric` 必须成对产生，重心三分量之和在容差内等于 1，`local_normal` 必须为有限的单位向量。Schema 的 `anchor_3d.uv` 表示资产表面/纹理 UV；RealityKit `TriangleHit.uv` 是三角形内的重心二元坐标，必须先转换成三分量 `barycentric`，不得直接混写。

## 区域本体决策

- `region_id` 是稳定机器身份；
- 中文名称、未来其他语言和用户同义词是可变显示层；
- 左右侧不得藏在名称里；
- 区域有父子层级、允许表面、允许深度和审核状态；
- 默认模型使用宽泛身体区域；
- 专业模型实体映射到本体，但实体 ID 不替代 `region_id`；
- 用户点击专业实体只表示“感觉在该结构附近”，不形成受伤组织结论；
- 未审核实体不得进入组织级报告或 Agent 事实。

## Marker 与 Event 的关系

- `BodyMarker` 是一次位置表达的可视对象；
- `BodyLocation` 是位置事实；
- `BodySignalEvent` 是带时间、感觉、程度、诱因和影响的确认事件；
- 一个 Event 可以包含多个 Marker；
- 同一位置可以在多个 Check-in 中复用或重新确认；
- Marker 的选中、高亮和颜色是瞬时显示状态，不属于 Event；
- “已缓解”通过新 Check-in 表达，不是 Marker 三态；
- 已确认事件修改生成 Revision，不静默覆盖原始位置。

## 跨视图规则

1. 2D、默认 3D、专业 3D 渲染同一 Marker UUID。
2. 切换视图不创建新 BodyLocation 或 Event。
3. `region_id`、左右侧、表面和 Episode 不随视图改变。
4. 精确点映射不足时退到区域级显示并要求复核。
5. 2D/列表是 3D 不可用时的完整等价路径。
6. 专业模型可提高显示颗粒度，但不得自动提升事实精度。

## 迁移规则

### 同拓扑

- 校验资产版本和 topology ID；
- 使用 triangle + barycentric 重建；
- 校验局部点误差和区域一致；
- 不覆盖原锚点。

### 不同 LOD

- 优先使用固定 Canonical Collision Mesh；
- 或使用离线预计算的 LOD 对应；
- 不用最近世界点作为唯一迁移方式。

### 默认模型与专业模型

- 使用规范表面空间；
- 校验区域、侧别和表面；
- 保存 `mapping.confidence`；
- 低置信时 `mapping.reviewed_by_user=false`，必须由用户复核；
- 专业实体只作为候选显示。

### 资产升级

迁移记录保留原/新资产、原/新锚点、算法版本、置信度、审核或用户复核状态。历史报告继续引用当时版本。

## 不变量

- 世界坐标不是唯一持久化位置；
- 屏幕坐标不是持久化位置；
- 文字列表不得以代表性点或显示名称伪造精确针点；
- 显示名称不是区域主键；
- 数组下标不是区域主键；
- 视图切换不改变业务事实；
- 资产升级不静默移动旧标记；
- 未确认候选不进入权威档案；
- AI 推断不覆盖用户位置；
- 删除草稿不删除确认事件；
- 用户依法删除可删除个人内容，“追加式”只描述正常版本历史。

## 选择该方案的原因

- 将长期身体档案与任何单一模型解耦；
- 支持 2D、默认 3D 和专业 3D 一致；
- 允许模型、LOD 和显示名称演进；
- 可追溯精确点与区域级语义；
- 明确表达不确定性；
- 避免把专业模型实体误当医学诊断；
- 支持离线、回放、报告和 Agent 工具使用同一事实层；
- 使迁移和验收可自动测试。

## 被否决的替代方案

### A. 每种视图各存一套标记

否决原因：重复、冲突、难以跨视图比较，报告无稳定身份。

### B. 只存 3D 世界坐标

否决原因：相机/模型变换、资产替换、姿势和版本都会导致漂移。

### C. 只存区域 ID

否决原因：丢失用户精确表达，无法回放 Point、区域内位置和放射路径。

### D. 只存三角形下标

否决原因：拓扑和 LOD 一变即失效；必须同时有资产版本和规范表面锚点。

### E. 最近手写中心或最近 3D 点

否决原因：会填满未定义空间、跨边界、跨侧和跨模型，不表达不确定性。RehabMate 的区域算法属于这一类。

### F. 专业模型实体名直接作为事实

否决原因：实体命名随供应商变化，用户表面感觉不能证明组织损伤。

## 后果

### 正面

- 所有客户端视图和报告共享稳定位置；
- 资产可替换而不丢失原始事实；
- 能量化迁移置信度和要求用户复核；
- 无障碍列表与图形输入真正等价；
- Agent 只读取用户确认的结构化位置；
- 审计可以还原当时使用的模型和映射。

### 成本

- 需要维护区域本体、规范表面图和资产对应表；
- 资产流水线和黄金点测试成本增加；
- 跨不同形体的精确点无法始终自动映射；
- 必须保留旧资产证据或迁移信息；
- UI 需要处理低置信和用户复核，而不是总给出确定答案。

这些成本是长期身体档案可靠性的必要成本。

## 验证

- 2D/默认/专业切换后 UUID、区域、侧别和 Episode 100% 一致；
- 同拓扑表面重建误差目标 ≤1 mm；
- 锁定黄金测试中左右侧错误为 0；
- 区域内部黄金点命中率目标 ≥95%；
- 边界点 100% 显示不确定/候选；
- 低置信跨模型映射 100% 要求复核；
- 重启、同步、离线恢复后锚点不漂移；
- 资产升级不覆盖旧锚点；
- VoiceOver 列表路径产生相同 schema；
- 点击专业实体不会写入损伤组织字段。

## 实施顺序

1. 冻结 Canonical Body Space；
2. 完成首发区域本体和稳定 ID；
3. 定义 `BodyLocation` schema 与版本策略；
4. 制作 2D 路径和默认碰撞模型；
5. 建立 2D/3D 对应与黄金测试；
6. 接入专业模型的稳定实体映射；
7. 实现低置信复核和资产迁移记录；
8. 最后才连接 Agent、报告和趋势。

## 变更策略

以下变化需要替代 ADR，而不是直接修改实现：

- 改变坐标轴或左右约定；
- 取消 `region_id` 或让显示名称成为主键；
- 允许世界/屏幕坐标成为唯一锚点；
- 改变用户确认边界；
- 允许专业实体自动成为损伤事实；
- 取消原锚点和迁移记录；
- 允许每个视图独立持久化身体位置。

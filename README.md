# moon-lot-recall

[![CI](https://github.com/liyun6666/moon-lot-recall/actions/workflows/ci.yml/badge.svg)](https://github.com/liyun6666/moon-lot-recall/actions/workflows/ci.yml)

**MoonBit 食品批次召回影响追踪库与离线命令行工具。** 输入批次、加工、出货和召回线索，输出可能受影响的下游批次、收货方、证据路径、账面库存与待核查事项。适合食品厂、中央厨房、仓配团队把分散的 ERP 导出表快速整理成可审查的召回工作单。

本项目分析的是**可能暴露的范围**。加工中的混料会保守地标记全部输出批次；路径不等于污染证据，账面库存不等于现场库存。工具不会自动发通知、判定食品安全或宣称法定召回完成。

## 30 秒试用

安装 [MoonBit](https://www.moonbitlang.com/download/) 与 Node.js，然后在仓库根目录运行：

```sh
moon update
moon test --warn-list=-implicit_impl_as_method --deny-warn
moon run cmd/main --target js --warn-list=-implicit_impl_as_method -- analyze examples/bakery-ledger.json examples/bakery-recall.json markdown
moon run cmd/main --target js --warn-list=-implicit_impl_as_method -- actions examples/bakery-ledger.json examples/bakery-recall.json
moon run cmd/main --target js --warn-list=-implicit_impl_as_method -- readiness examples/bakery-ledger.json examples/bakery-recall.json examples/bakery-counts.csv examples/bakery-responses.csv
```

示例是**虚构的面包店数据**：`FLOUR-A → DOUGH-A → BREAD-A`，因此 `OUT-101` 和 `OUT-102` 进入收货方核查表；由 `FLOUR-B` 制成的 `BREAD-B` 不在范围内。现场盘点 `BREAD-A` 比账面少 50 克，`OUT-102` 仅有一次联系尝试，所以证据检查仍有未完成项。

## 数据与功能

| 能力 | 输入 | 输出及用途 |
| --- | --- | --- |
| 校验 | 批次、加工、出货记录 | 重复 ID、未知引用、时间倒置、质量不守恒、超额分配等诊断；无效数据拒绝分析 |
| 下游追踪 | 召回种子批次、截点 | 受影响批次、出货、从种子到输出的加工路径 |
| 多来源归因 | 多个可疑种子批次 | 每个输出批次对应的所有可达种子及路径 |
| 上游追踪 | 目标批次、截点 | 生产链上的原料来源和路径 |
| 库存与行动 | 同一账本、召回请求 | 账面可控数量、待核查出货和人工处理清单 |
| 盘点对账 | 现场盘点 CSV | 账面与实测差额、缺失盘点、盘点凭证 |
| 收货方合并 | 受影响出货 | 每个收货方一份待复核清单，避免重复联系 |
| 联系进度 | 人工填写的联系事件 CSV | 待联系、已尝试、已联系、已确认和失败的证据履历 |
| 截点差异 | 原截点、新截点 | 新增受影响批次、出货，便于更新范围 |
| 证据清单 | 盘点与联系记录 | 未盘点、库存差额、未确认出货等未完成项 |

CLI 支持 JSON、Markdown 和面向人工表格的 CSV 导出。CSV 中可能被表格软件解释成公式的文本会加前导单引号。

### 文件格式

- `examples/bakery-ledger.json`：`schema_version: 1`；`lots`、`transformations`、`shipments`。批次 ID 在账本内唯一。数量是整数克，时间是 Unix 秒。JSON 的 `Int64` 字段使用**字符串**表示，以免 JavaScript 丢精度。
- `examples/bakery-recall.json`：`id`、`reason`、`seed_lots`、`as_of`。
- `examples/lots.csv`、`transformations.csv`、`shipments.csv`：对应三张 ERP 导出表。加工表每行一个输入或输出分量，`direction` 为 `input` 或 `output`。
- `examples/bakery-counts.csv`：`lot_id,facility,counted_g,counted_at,reference`。盘点时间必须等于分析截点；缺失批次会显式列出。
- `examples/bakery-responses.csv`：`shipment_id,status,recorded_at,reference,note`。按文件顺序记录状态变化；`acknowledged` 必须先有 `reached`。

### 命令

以下省略通用前缀 `moon run cmd/main --target js --warn-list=-implicit_impl_as_method --`：

```text
validate LEDGER.json
analyze LEDGER.json RECALL.json [json|markdown|csv]
actions LEDGER.json RECALL.json
inventory LEDGER.json AS_OF
upstream LEDGER.json LOT_ID AS_OF
import-csv LOTS.csv TRANSFORMATIONS.csv SHIPMENTS.csv OUT.json
reconcile LEDGER.json COUNTS.csv AS_OF [json|markdown]
consignees LEDGER.json RECALL.json [json|markdown|csv]
responses LEDGER.json RECALL.json EVENTS.csv [json|markdown]
delta LEDGER.json RECALL.json NEW_AS_OF [json|markdown]
readiness LEDGER.json RECALL.json COUNTS.csv EVENTS.csv [json|markdown]
```

CLI 遇到无效记录返回非零退出码，适合放入数据导入流程。`import-csv` 只在整份账本通过校验后写出 JSON。所有分析在本机运行；示例没有连接食品监管数据库或客户通讯系统。

## 业务边界

一笔加工事件把**全部输入**连接到**全部输出**，用于混料、分装等保守影响追踪。模型把一个批次放在一个设施；跨设施调拨需要在源系统转换成收发记录后导入，当前版本不会臆造转运。出货指向外部收货方，不代表收货方库存、销售量或消费者范围。若企业没有完整批次编码、加工记录或出货记录，报告无法覆盖缺失链路，必须先补齐来源数据。

`ReadinessReport.evidence_review_complete` 只表示**本工具清单中的盘点差额已消除且出货有确认记录**。它不是法律合规或食品安全结论。真实召回仍需质量负责人核实记录、现场封存、依法通知和监管沟通。

## 开发与验证

```sh
moon fmt
moon info
moon check --target js --warn-list=-implicit_impl_as_method --deny-warn
moon test --warn-list=-implicit_impl_as_method --deny-warn
```

测试覆盖多步加工、混料、无关批次、时间截点、CSV 转义与非法数据拒绝、盘点差额、收货方合并、联系状态转换、增量报告和证据清单。仓库的 `.github/workflows/ci.yml` 在推送和 PR 时运行同样的检查并执行 CLI 示例。

## 原创与参考

本项目为原创 MoonBit 实现，不移植现有代码。数据交换与可追溯理念参考 [GS1 EPCIS 2.0](https://www.gs1.org/standards/epcis)，食品召回场景参考 [FDA 食品召回开放数据](https://open.fda.gov/apis/food/)。当前版本没有声称兼容完整 EPCIS 事件格式，也没有把 FDA 数据当成企业内部批次事实。源代码采用 [Apache License 2.0](LICENSE)。

# 服务器 PCIe 错误类型与排障指南

## 1. PCIe 与 AER 概述

PCIe（PCI Express）是现代服务器中 CPU 与外围设备（GPU、NVMe SSD、网卡等）之间的高速串行总线标准，采用分层架构（物理层、数据链路层、事务层）实现高带宽、低延迟的数据传输。

AER（Advanced Error Reporting）是 PCIe 规范定义的可选高级功能，属于 PCIe 的 Advanced Features 之一。与传统的 PCI 奇偶校验（Parity Error）仅能报告"发生了错误"不同，AER 可以精确记录错误类型、严重等级、发起设备以及错误发生位置，极大提升了硬件故障定位的效率。支持 AER 的设备会在 PCIe Extended Capability 空间中暴露 AER Capability 结构（Capability ID = 0x0001），操作系统通过读取该结构获取详细错误日志。

**核心概念**：

| 概念 | 说明 |
|------|------|
| **AER Capability** | PCIe Extended Capability 结构，存放 AER 控制和状态寄存器 |
| **Correctable Error** | 硬件可自动纠正的错误，无需软件干预，不影响数据传输完整性 |
| **Uncorrectable Non-Fatal** | 硬件无法纠正但链路可恢复的错误，事务层协议（如 TLP）可能丢失，但链路本身不降级 |
| **Uncorrectable Fatal** | 硬件无法纠正且链路不可恢复的严重错误，通常导致设备功能丧失或系统崩溃 |
| **Root Port / Root Complex** | AER 错误通常由 Root Port 或 Root Complex Event Collector 收集并上报到 OS |
| **BDF (Bus:Device.Function)** | PCIe 设备在系统中的唯一地址，如 `0000:17:00.0`，用于定位具体故障设备 |

## 2. AER 错误类型完整列表

### 2.1 Correctable Errors（可纠正错误）

| 错误类型 | 寄存器位 | 说明 | 常见原因 |
|----------|:--------:|------|----------|
| Receiver Error | Bit 0 | 物理层接收端检测到信号错误，通常由 8b/10b 或 128b/130b 编码异常触发 | 信号质量差、线缆老化/松动、插槽接触不良、EMI 干扰 |
| Bad TLP | Bit 6 | 事务层（Transaction Layer）收到格式错误的 TLP（Transaction Layer Packet），如 LCRC 校验失败 | 对端设备固件 Bug、链路信号退化、时钟抖动 |
| Bad DLLP | Bit 7 | 数据链路层（Data Link Layer）收到格式错误的 DLLP（Data Link Layer Packet），CRC 校验失败 | 链路质量差、线缆或连接器问题 |
| REPLAY_NUM Rollover | Bit 8 | 数据链路层的重传计数器溢出。当对端因反复收到错误包而不断请求重传，重传次数超过上限（通常为 4 次，即 REPLAY_NUM = 11b）时触发 | 链路不稳定、信号完整性问题持续存在 |
| Replay Timer Timeout | Bit 12 | 数据链路层的重传计时器超时。发送端在预期时间内未收到对端的 ACK/NAK 响应，无法确认 TLP 是否到达 | 对端设备无响应或响应过慢、设备固件挂起、链路中断 |
| Advisory Non-Fatal Error | Bit 13 | 设备通过 Advisory Non-Fatal Error 机制上报的提醒性错误，特定于厂商实现 | 厂商特定的健康监控触发 |

### 2.2 Uncorrectable Errors（不可纠正错误）

#### Non-Fatal（非致命）

| 错误类型 | 寄存器位 | 说明 | 常见原因 |
|----------|:--------:|------|----------|
| Data Link Protocol Error | Bit 4 | 数据链路层协议状态机异常，例如收到非预期的 DLLP 序列、ACK/NAK 时序异常 | PCIe 链路训练（Link Training）失败、设备侧 DLLP 引擎故障 |
| Surprise Down Error | Bit 5 | 设备在未通过软件正常卸载的情况下被移除或失去响应。仅支持热插拔的插槽会报告此错误 | 物理热插拔操作、设备掉电、线缆意外断开、硬盘托架松动 |
| Poisoned TLP Received | Bit 12 | 收到被上游设备标记为"Poisoned"的 TLP，表示该 TLP 关联的数据已损坏 | 上游设备内存 ECC 错误向外传播、上游设备的 Uncorrectable 错误级联 |
| Completion Timeout | Bit 14 | 设备发起 Non-Posted Request 后，在 Completion Timeout 时间内未收到 Completion | 对端设备处理过慢或挂死、PCIe 交换芯片（Switch）故障、设备固件卡死 |
| Completer Abort | Bit 15 | 目标设备无法完成请求，主动以 Completer Abort (CA) 终止事务 | 设备内部错误（如内部总线超时、固件异常）、请求目标地址越界 |
| Unexpected Completion | Bit 16 | 收到一个与当前任何未决请求不匹配的 Completion | 设备状态与 Root Complex 不同步、AER 固件首来（Firmware First）模式下的异步事件、设备 ID 路由错误 |
| ACS Violation | Bit 18 | 违反了 ACS（Access Control Services）的访问控制策略，如 P2P Request Redirect / ACS P2P Egress Control 规则被触发 | 虚拟化环境中的 IOMMU 分组配置错误、SR-IOV VF 间非法通信尝试 |
| Uncorrectable Internal Error | Bit 22 | 设备内部检测到一个不可纠正的内部错误，超出 AER 标准定义的错误类型范围 | 设备硬件逻辑故障、内部总线超时、片上 SRAM ECC 不可纠正错误 |
| MC Blocked TLP | Bit 23 | 由于访问控制服务（ACS）或地址翻译服务（ATS）策略，某个 TLP 被阻塞 | IOMMU 配置策略异常、ATS Translation 缺失、多主机系统路由策略冲突 |
| AtomicOp Egress Blocked | Bit 24 | 出口端口因路由问题阻止了一个 Atomic Operation 请求 | 交换芯片不支持 AtomicOp 转发、下游端口不兼容 |
| TLP Prefix Blocked | Bit 25 | 出口端口因不支持 TLP Prefix（如 End-to-End TLP Prefix）而阻止了该 TLP | 链路两端设备 TLP Prefix 能力不匹配、交换机不支持透传 |

#### Fatal（致命）

| 错误类型 | 寄存器位 | 说明 | 常见原因 |
|----------|:--------:|------|----------|
| Undefined / Reserved | Bit 0 | 未定义的致命错误，通常表示设备返回了无效的错误编码 | 设备硬件设计缺陷、ASIC Bug |
| Malformed TLP | Bit 1 | 接收到严重格式错误的 TLP，如长度字段与实际数据不匹配、地址/数据对齐错误 | 设备硬件故障、ASIC 逻辑错误、PCB 走线信号完整性严重退化 |
| ECRC Error | Bit 2 | End-to-End CRC 校验失败。发送端在 TLP Digest 字段附加 ECRC，接收端校验不通过 | 链路信号完整性差、Switch 中继转发损坏数据、时钟偏差 |
| Unsupported Request (UR) | Bit 3 | 设备收到无法识别的请求类型，或请求的目标寄存器/地址空间不存在 | 驱动发送不支持的命令、设备配置空间访问越界、固件和驱动版本不匹配 |
| Flow Control Protocol Error | Bit 13 | 数据链路层的流控信用（Flow Control Credit）机制异常，如信用透支或信用泄漏 | 设备 DLLP 引擎缺陷、链路信用同步状态丢失 |
| Receiver Overflow | Bit 17 | 接收端缓冲溢出，无法容纳传入的 TLP，通常表示设备接收能力不足以匹配链路速率 | 设备内部拥塞、DMA 引擎处理速度不足、Switch 仲裁策略不合理 |

> **注意**：并非所有 PCIe 设备都会报告上述全部错误类型。实际可报告的错误取决于设备的 AER Capability 寄存器中的 Error Mask 设置和设备驱动配置。

## 3. 错误严重等级与判定标准

| 等级 | 图标 | 判定条件 |
|:----:|:----:|----------|
| 正常 | 🟢 | AER 错误计数器中无任何错误记录，`dmesg` / `journalctl` 无 `aer:` 相关日志 |
| 预警 | 🟡 | 满足以下任一条件：① 出现偶发 Correctable Error（如单个 Receiver Error），且一段时间内未再现；② Correctable Error 频率较低（每秒 < 10 次），且无递增趋势；③ 首次检测到 Bad DLLP / Replay Timer Timeout 但随后恢复 |
| 严重 | 🔴 | 满足以下任一条件：① 出现任何 Uncorrectable Error（Non-Fatal 或 Fatal）；② Correctable Error 短时间内高频爆发（每秒 > 10 次）且持续不降；③ REPLAY_NUM Rollover 被触发（说明链路回退到重传极限）；④ 同一设备反复上报 Surprise Down Error；⑤ 出现 Poisoned TLP / Completion Timeout / Malformed TLP 等 Fatal 级错误 |

### 附加判断维度

| 维度 | 判断方法 |
|------|----------|
| 趋势分析 | 对同一设备的 AER 错误进行时间序列采样。若 Correctable Error 在 1 小时内持续递增，即使频率未达阈值也应升级为预警 |
| 多设备关联 | 若同一 Root Port 下的多个设备同时上报 Correctable Error，应优先怀疑 Root Port 或上游 Switch 的物理链路问题 |
| 业务影响 | 即使错误等级为预警，若已导致业务感知到延迟增加或间歇性 IO 超时，应升级为严重 |

## 4. 处置建议

### 4.1 Correctable Error — 偶发（预警）

| 步骤 | 操作 |
|:----:|------|
| 1 | 持续观察 24 小时，记录错误频率和趋势 |
| 2 | 检查链路带宽是否正常（`lspci -vvv -s <BDF>` 查看 LnkSta 中的 Speed 和 Width） |
| 3 | 若频率有增长趋势，进入高频处置流程 |
| 4 | 记录事件到维护日志，标记设备为"观察中"状态 |

### 4.2 Correctable Error — 高频（预警→严重）

| 步骤 | 操作 |
|:----:|------|
| 1 | 通知运维团队，评估对业务的影响 |
| 2 | 物理检查：重新插拔 PCIe 卡或线缆，确认连接牢固 |
| 3 | 检查并升级设备固件到厂商推荐的最新版本 |
| 4 | 若使用 PCIe 延长线/Riser 卡，尝试更换线缆或插槽位置 |
| 5 | 对比同型号其他设备是否也出现同类错误（排查批次问题） |
| 6 | 若更换线缆/插槽后仍未改善，排期更换设备 |

### 4.3 Uncorrectable Non-Fatal（严重）

| 步骤 | 操作 |
|:----:|------|
| 1 | 记录完整 AER 日志（包括 BDF、错误类型、时间戳） |
| 2 | 尝试软件恢复：对设备执行 Function-Level Reset (`echo 1 > /sys/bus/pci/devices/<BDF>/reset`) 或 Hot Reset |
| 3 | 若设备为 NVMe SSD，检查文件系统是否受损，必要时执行 `fsck` |
| 4 | 复现监测：若同一设备在 1 小时内再次触发 Uncorrectable Non-Fatal，立即进入更换流程 |
| 5 | 更换故障设备。更换前确保备件型号、固件版本兼容 |

### 4.4 Uncorrectable Fatal（严重）

| 步骤 | 操作 |
|:----:|------|
| 1 | 立即通告运维和业务团队，启动应急响应 |
| 2 | 立即将受影响服务器从生产流量中摘除 |
| 3 | 记录完整 AER 日志信息，截图保存 |
| 4 | 若为存储类设备（NVMe SSD），检查数据完整性和 RAID 状态 |
| 5 | 更换故障 PCIe 设备，必要时更换对应插槽所在的 Riser 卡或主板 |
| 6 | 更换后运行厂商诊断工具进行压力测试，通过后方可上线 |
| 7 | 复盘分析：对比同批次、同型号设备的 AER 日志历史，排查共性问题 |

### 4.5 链路带宽降级检测

AER 报告错误同时，应一并检查链路训练状态。链路降级（如从 Gen4 x8 降速到 Gen1 x1）通常是物理问题的早期信号。

```bash
# 查看链路能力和当前状态
lspci -vvv -s <BDF> 2>/dev/null | grep -E "LnkCap:|LnkSta:|LnkCtl:"

# 示例输出解读
# LnkCap: Speed 16GT/s, Width x8  → 硬件能力：PCIe Gen4 x8
# LnkSta: Speed 2.5GT/s, Width x1  → 当前状态：已降速到 Gen1 x1 → 严重！
```

判定规则：
- 链路速率低于硬件能力的 50% → 🟡 预警
- 链路速率降低到 Gen1 或 x1 → 🔴 严重，需立即排查

## 5. Linux 日志识别

### 5.1 dmesg 典型日志格式

```text
# Correctable Error（可纠正错误）
pcieport 0000:00:1c.0: AER: Corrected error received: id=00e0
pcieport 0000:00:1c.0: AER: Multiple Corrected error received: id=00e0
pcieport 0000:00:1c.0: PCIe Bus Error: severity=Corrected, type=Physical Layer, id=00e0(Receiver ID)
pcieport 0000:00:1c.0:   device [8086:7abc] error status/mask=00000001/00002000
pcieport 0000:00:1c.0:    [ 0] RxErr                  (First)

# Uncorrectable Non-Fatal Error（不可纠正非致命）
pcieport 0000:00:1c.0: AER: Uncorrected (Non-Fatal) error received: id=00e0
pcieport 0000:00:1c.0: PCIe Bus Error: severity=Uncorrected (Non-Fatal), type=Transaction Layer, id=00e0(Requester ID)
pcieport 0000:00:1c.0:   device [8086:7abc] error status/mask=00100000/00000000
pcieport 0000:00:1c.0:    [20] UnsupReq               (First)

# Uncorrectable Fatal Error（不可纠正致命）
pcieport 0000:00:1c.0: AER: Uncorrected (Fatal) error received: id=00e0
pcieport 0000:00:1c.0: PCIe Bus Error: severity=Uncorrected (Fatal), type=Transaction Layer, id=00e0(Requester ID)
pcieport 0000:00:1c.0:   device [8086:7abc] error status/mask=00000004/00000000
pcieport 0000:00:1c.0:    [ 2] ECRC                    (First)
```

### 5.2 日志字段说明

| 字段 | 说明 | 示例 |
|------|------|------|
| `pcieport 0000:00:1c.0` | 报告错误的 Root Port BDF 地址。`0000:` 是 PCIe Domain，`00:` 是 Bus，`1c:` 是 Device，`.0` 是 Function | `0000:00:1c.0` |
| `id=00e0` | 错误源设备在 Root Port 内的 Requester ID 或 Receiver ID | `00e0`（Bus 0, Device 1c, Fun 0 的编码值） |
| `severity=Corrected` | 错误严重等级：Corrected / Uncorrected (Non-Fatal) / Uncorrected (Fatal) | — |
| `type=Physical Layer` | 错误发生的协议层：Physical Layer / Data Link Layer / Transaction Layer | — |
| `device [8086:7abc]` | PCI Vendor ID : Device ID，`8086` = Intel，可通过 `lspci -nn` 对照确认 | `[8086:7abc]` |
| `error status/mask` | 当前错误状态寄存器值 / 已屏蔽的错误位掩码 | `00000001/00002000` |
| `[ 0] RxErr` | 错误位号和名称，`First` 表示是该位首次触发（非首次为 `Not First`） | `[ 0] RxErr` |

### 5.3 常用排查命令

```bash
# 查看系统所有 AER 错误日志
dmesg | grep -i "aer:" | tail -50

# 查看某个 Root Port 下的子设备拓扑
lspci -t -v

# 查看特定设备的 AER 能力（必须 root）
lspci -vvv -s <BDF> | grep -A 20 "Advanced Error Reporting"

# 通过 sysfs 查看设备的 AER 统计计数器（需要 root）
cat /sys/bus/pci/devices/<BDF>/aer_dev_correctable
cat /sys/bus/pci/devices/<BDF>/aer_dev_fatal
cat /sys/bus/pci/devices/<BDF>/aer_dev_nonfatal

# 查看 Root Port 汇总的 AER 统计
cat /sys/bus/pci/devices/0000:00:1c.0/aer_rootport_total_err_cor
cat /sys/bus/pci/devices/0000:00:1c.0/aer_rootport_total_err_fatal
```

### 5.4 BDF 地址解析方法

BDF（Bus:Device.Function）格式 `0000:17:00.0` 解析：

| 字段 | 位置 | 含义 |
|------|------|------|
| `0000` | Domain | PCIe 域编号，多主机或虚拟化环境可能存在多个 Domain |
| `17` | Bus | 总线号（0–255），由 BIOS/UEFI 枚举时分配 |
| `00` | Device | 设备号（0–31），在总线上唯一 |
| `.0` | Function | 功能号（0–7），一个物理设备可有多个独立 Function |

## 6. 来源

- **PCI-SIG PCI Express Base Specification, Revision 5.0/6.0, Chapter 6 — Advanced Error Reporting (AER)**：定义 AER Capability 结构、错误分类与寄存器定义
- **Linux Kernel PCIe AER Driver Documentation** (`Documentation/PCI/pcieaer-howto.rst`)：Linux 内核 AER 驱动实现、sysfs 接口和日志格式说明
- **PCI-SIG ECN: Advanced Error Reporting**：AER 扩展的 Engineering Change Notice，包含 Correctable / Uncorrectable Error Status Register 完整位定义

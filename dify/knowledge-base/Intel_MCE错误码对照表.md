---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 83a777a8d7991068fec5ab55d75207d5_a7840b5a7c3611f1baf4525400bff409
    ReservedCode1: i29Si3O5cGiANCWdOJbAalJsnp/lnv9cIGE5SmoSq4U8LoWnD1UDgWcZQwCaZ5Xv1vHWI7Cn7QfmL3HnOK1Ep/5s963iYQoViAC0iyOOX8yJ5Relrt6T21LItmHyaYGo7C/f08/wnHfd0f8gY3yajp7o5CDdDhvkgQoaDM+HfNBDXqHuWlUbC8zL2yI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 83a777a8d7991068fec5ab55d75207d5_a7840b5a7c3611f1baf4525400bff409
    ReservedCode2: i29Si3O5cGiANCWdOJbAalJsnp/lnv9cIGE5SmoSq4U8LoWnD1UDgWcZQwCaZ5Xv1vHWI7Cn7QfmL3HnOK1Ep/5s963iYQoViAC0iyOOX8yJ5Relrt6T21LItmHyaYGo7C/f08/wnHfd0f8gY3yajp7o5CDdDhvkgQoaDM+HfNBDXqHuWlUbC8zL2yI=
---

# Intel MCE 错误码对照表

## 1. MCA 概述

Machine-Check Architecture (MCA) 是 Intel 处理器（Pentium 4、Intel Xeon、Intel Atom 及 P6 family）实现的一套硬件错误检测与报告机制。它由一组 Model-Specific Registers (MSRs) 组成，用于配置 machine checking 以及记录检测到的硬件错误，包括：system bus errors、ECC errors、parity errors、cache errors 和 TLB errors。当处理器检测到 uncorrected machine-check error 时，会生成 machine-check exception (#MC，abort 类异常)；对于 corrected errors，处理器可通过 CMCI (Corrected Machine-Check Error Interrupt) 向软件报告。

> **注意**：本文档内容来自 Intel SDM Vol. 3B (Dec 2024 版本) Chapter 17。在更早版本的 SDM 中，该章节编号为 Chapter 15。

---

## 2. MCi_STATUS 寄存器关键字段

每个 IA32_MCi_STATUS MSR 包含与 machine-check error 相关的信息（当 VAL 位置位时有效）。以下是寄存器的关键位字段定义：

| 位范围 | 字段名 | 说明 |
|--------|--------|------|
| 0-15 | MCA Error Code | Machine-check architecture 定义的 16-bit 错误码。对所有实现 MCA 的 IA-32 处理器保持一致。详见 Section 17.9 及 Chapter 18。 |
| 16-31 | Model-Specific Error Code | 模型特定的错误码，用于唯一标识检测到的 machine-check error 条件。不同处理器上同一错误条件的编码可能不同。 |
| 32-36 | Other Information | 实现特定的附加信息（当 MCG_EMC_P = 0 时 bits 37:32；当 MCG_EMC_P = 1 时 bits 36:32）。不属于 machine-check architecture 的组成部分。 |
| 37 | Firmware Updated Status | 当 MCG_EMC_P = 1 时有效。0 = 系统固件未修改 IA32_MCi_STATUS 内容；1 = 系统固件可能已编辑 IA32_MCi_STATUS 内容。 |
| 38-52 | Corrected Error Count | 当 MCG_CMCI_P = 1 时为架构级字段。15-bit 计数器，每次 corrected error 被该 bank 观测到时递增，由软件清零。Bit 52 为 sticky count overflow bit。 |
| 53-54 | Threshold-Based Error Status | 当 MCG_TES_P = 1 且 UC = 0 时有效。指示硬件结构的阈值跟踪状态：00 = No tracking；01 = Green（低于阈值）；10 = Yellow（高于阈值）；11 = Reserved。当 UC = 1 时，这些位未定义。 |
| 55 | AR (Action Required) | 当 MCG_TES_P = 1 且 MCG_CAP[24] = 1 时有效。置位时表示系统软件必须对 MCA error code 执行特定的 recovery action。详见 Section 17.6.2。 |
| 56 | S (Signaling) | 当 MCG_TES_P = 1 且 MCG_CAP[24] = 1 时有效。置位时表示此 MC bank 正在报告 UCR (Uncorrected Recoverable) 错误。详见 Section 17.6.2。 |
| 57 | PCC (Processor Context Corrupted) | 置位时表示处理器状态可能已被错误条件损坏，可能无法可靠重启。清零时表示错误未影响处理器状态，软件可能可以重启。 |
| 58 | ADDRV (MCi_ADDR Valid) | 置位时表示 IA32_MCi_ADDR 寄存器包含错误发生地址。清零时表示该寄存器未实现或不含地址信息。 |
| 59 | MISCV (MCi_MISC Valid) | 置位时表示 IA32_MCi_MISC 寄存器包含关于错误的附加信息。清零时表示该寄存器未实现或不含附加信息。 |
| 60 | EN (Error Enabled) | 置位时表示该错误已被 IA32_MCi_CTL 寄存器中对应的 EEj 位使能。 |
| 61 | UC (Uncorrected Error) | 置位时表示处理器未能或无法纠正该错误条件。清零时表示处理器已成功纠正该错误。 |
| 62 | OVER (Machine Check Overflow) | 置位时表示在前一个错误结果仍在 error-reporting register bank 中（即 VAL 位已置位）时发生了新的 machine-check error。由处理器置位，软件负责清零。 |
| 63 | VAL (MCi_STATUS Valid) | 置位时表示 IA32_MCi_STATUS 寄存器中的信息有效。由处理器置位，软件负责清零（写入 0）。 |

---

## 3. 常见 Simple Error Codes

以下来自 Table 17-9，编码为 IA32_MCi_STATUS[15:0] 的 Simple Error Codes：

| 错误码 (Hex) | 错误码 (Binary) | 说明 |
|-------------|-----------------|------|
| 0x0000 | 0000 0000 0000 0000 | No Error — 此 error-reporting bank 未报告任何错误。 |
| 0x0001 | 0000 0000 0000 0001 | Unclassified — 此错误未被归类到 MCA error classes。 |
| 0x0002 | 0000 0000 0000 0010 | Microcode ROM Parity Error — 内部微码 ROM 奇偶校验错误。 |
| 0x0003 | 0000 0000 0000 0011 | External Error — 来自另一处理器的 BINIT# 信号导致本处理器进入 machine check。 |
| 0x0004 | 0000 0000 0000 0100 | FRC Error — FRC (Functional Redundancy Check) 主/从错误。 |
| 0x0005 | 0000 0000 0000 0101 | Internal Parity Error — 内部奇偶校验错误。 |
| 0x0006 | 0000 0000 0000 0110 | SMM Handler Code Access Violation — SMM Handler 尝试在 SMRR 指定范围之外执行代码。 |
| 0x0400 | 0000 0100 0000 0000 | Internal Timer Error — 内部定时器错误。 |
| 0x0E0B | 0000 1110 0000 1011 | I/O Error — 通用 I/O 错误。 |
| 0x01xx | 0000 01xx xxxx xxxx | Internal Unclassified — 内部未分类错误。至少一个 'x' 位必须为 1。 |

---

## 4. Compound Error Codes

以下来自 Table 17-10，编码为 IA32_MCi_STATUS[15:0] 的 Compound Error Codes。Compound error codes 将 bits [15:0] 划分为多个 sub-field，用于描述 TLB、内存、缓存、总线/互连逻辑及内部定时器相关的错误。

### 4.1 Compound Error Code 类型总览

| 类型 | Form (Bits 15:0) | Interpretation |
|------|------------------|----------------|
| Generic Cache Hierarchy | 000F 0000 0000 11LL | Generic cache hierarchy error |
| TLB Errors | 000F 0000 0001 TTLL | {TT}TLB{LL}\_ERR |
| Memory Controller Errors | 000F 0000 1MMM CCCC | {MMM}\_CHANNEL{CCCC}\_ERR |
| Cache Hierarchy Errors | 000F 0001 RRRR TTLL | {TT}CACHE{LL}\_{RRRR}\_ERR |
| Extended Memory Errors | 000F 0010 1MMM CCCC | {MMM}\_CHANNEL{CCCC}\_ERR |
| Bus and Interconnect Errors | 000F 1PPT RRRR IILL | BUS{LL}\_{PP}\_{RRRR}\_{II}\_{T}\_ERR |

### 4.2 Correction Report Filtering (F) Bit

Bit 12 在 Intel Core Duo 及之后的处理器中用于指示 filtering 状态：
- **0**：Normal filtering（原始 P6/Pentium 4/Atom/Xeon 处理器语义）
- **1**：Corrected filtering — 该 line/entry 的过滤已激活，后续部分或全部 corrections 不会被 post。仅对 UC=0 有效，系统软件必须忽略 uncorrected errors 的 filtering bit。

### 4.3 Transaction Type (TT) Sub-Field (Bits 14:13)

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| I (Instruction) | 00 | 指令事务 |
| D (Data) | 01 | 数据事务 |
| G (Generic) | 10 | 通用（无法确定事务类型） |
| — | 11 | Reserved |

### 4.4 Level (LL) Sub-Field (Bits 11:10)

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| L0 | 00 | Level 0 |
| L1 | 01 | Level 1 |
| L2 | 10 | Level 2 |
| LG (Generic) | 11 | 通用（无法确定层级） |

### 4.5 Request (RRRR) Sub-Field (Bits 7:4)

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| ERR | 0000 | Generic Error |
| RD | 0001 | Generic Read |
| WR | 0010 | Generic Write |
| DRD | 0011 | Data Read |
| DWR | 0100 | Data Write |
| IRD | 0101 | Instruction Fetch |
| PREFETCH | 0110 | Prefetch |
| EVICT | 0111 | Eviction |
| SNOOP | 1000 | Snoop |
| PW | 1001 | Page Walk |
| EPW | 1010 | EPT Page Walk |

### 4.6 Bus and Interconnect Sub-Fields

**PP (Participation)** — Bits 12:11：

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| SRC | 00 | Local processor originated request |
| RES | 01 | Local processor responded to request |
| OBS | 10 | Local processor observed error as third party |
| — | 11 | Generic |

**T (Time-out)** — Bit 9：

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| TIMEOUT | 1 | Request timed out |
| NOTIMEOUT | 0 | Request did not time out |

**II (Memory or I/O)** — Bits 8:7：

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| M | 00 | Memory Access |
| — | 01 | Reserved |
| IO | 10 | I/O |
| — | 11 | Other transaction |

### 4.7 Memory Controller Sub-Fields

**MMM (Memory Transaction Type)** — Bits 11:9：

| Mnemonic | Binary | 说明 |
|----------|--------|------|
| GEN | 000 | Generic undefined request |
| RD | 001 | Memory read error |
| WR | 010 | Memory write error |
| AC | 011 | Address/Command Error |
| MS | 100 | Memory Scrubbing Error |
| — | 101-111 | Reserved |

**CCCC (Channel)** — Bits 3:0：

| Value | 说明 |
|-------|------|
| 0000-1110 | Channel number |
| 1111 | Channel not specified |

---

## 5. CE/UE 判定方法

根据 IA32_MCi_STATUS 寄存器中的 **VAL** (bit 63) 和 **UC** (bit 61) 位，可判断错误的类型：

| VAL (Bit 63) | UC (Bit 61) | 判定结果 | 说明 |
|:---:|:---:|---|---|
| 0 | X | 无有效错误 | VAL 位未置位，IA32_MCi_STATUS 中不包含有效错误信息。软件应跳过此 bank。 |
| 1 | 0 | CE (Correctable Error) | UC 位清零，表示处理器已成功纠正该错误条件。该错误被硬件自动修复，系统可继续正常运行。 |
| 1 | 1 | UE (Uncorrectable Error) | UC 位置位，表示处理器未能或无法纠正该错误条件。这通常会触发 #MC exception。此时需进一步检查 PCC (bit 57)、S (bit 56)、AR (bit 55) 等位判断恢复可能性。 |

### 判定流程伪代码

```
FOR each bank i in 0..MAX_BANK_NUMBER:
    IF IA32_MCi_STATUS[63] (VAL) == 0:
        SKIP  // no valid error
    IF IA32_MCi_STATUS[61] (UC) == 0:
        // Correctable Error (CE)
        // UC=0 时位 54:53 提供 threshold-based error status
        Log corrected error; clear IA32_MCi_STATUS
    ELSE:
        // Uncorrectable Error (UE)
        IF IA32_MCi_STATUS[57] (PCC) == 1:
            // Processor context corrupted, may not restart reliably
        IF IA32_MCi_STATUS[56] (S) == 1 and IA32_MCi_STATUS[55] (AR) == 1:
            // SRAR error: software MUST take recovery action
        ELSE IF IA32_MCi_STATUS[56] (S) == 1 and IA32_MCi_STATUS[55] (AR) == 0:
            // SRAO error: software MAY take recovery action
```

### 特别注意

- 当 **UC=1, PCC=0** 时，可能有 SRAO (Software Recoverable Action Optional) 错误，尽管错误未被纠正但处理器状态未损坏，软件可选择进行恢复。
- 当 **UC=1, PCC=1, S=1, AR=1** 时，为 SRAR (Software Recoverable Action Required) 错误，软件必须执行 recovery action。
- OVER (bit 62) 置位表示发生了溢出，即在 VAL 位已置位时有新的错误发生。此时计数器 (bits 52:38) 可用于判断是否有额外的 corrected errors。
- CE 的 threshold-based error status (bits 54:53) 在 UC=0 时提供：00=No tracking, 01=Green, 10=Yellow, 11=Reserved。

---

## 6. 来源

Intel 64 and IA-32 Architectures Software Developer's Manual, Volume 3B, Chapter 17: Machine-Check Architecture (Order Number: 325384-084US, December 2024).

> 注：在较早版本（2018年之前）的 SDM 中，Machine-Check Architecture 位于 Volume 3A, Chapter 15。本文档提取自 Dec 2024 版本 (325384-sdm-vol-3abcd)，该版本中该章节编号为 Chapter 17 并位于 Volume 3B。

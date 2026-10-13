# 雙精度浮點數乘法器（FP64 Multiplier）

數位積體電路設計期末專題：用 Verilog 設計符合 IEEE 754 的雙精度（64-bit）浮點數乘法器，以 pipeline 架構跑在 2.0 GHz，從 RTL 一路做到 APR，並通過 Calibre DRC / LVS。

## 規格

| 訊號 | 方向 | 說明 |
| --- | --- | --- |
| `CLK` | input | 時脈，2.0 GHz（clock period 0.5 ns） |
| `RESET` | input | 同步 reset，high active |
| `ENABLE` | input | 為 1 時從 `DATA_IN` 讀入資料 |
| `DATA_IN[7:0]` | input | 每個 cycle 輸入 1 byte |
| `DATA_OUT[7:0]` | output | 每個 cycle 輸出 1 byte |
| `READY` | output | 為 1 時 `DATA_OUT` 是有效的結果 |

- 輸入：A、B 各 8 bytes，從低位 byte 開始送，共 16 個 cycle。
- 輸出：輸入完成後 8 個 cycle 拉高 `READY`，連續 8 個 cycle 送出結果，同樣從低位 byte 開始（題目要求 latency 小於 60 個 cycle）。
- 捨入模式為 round to nearest even。
- 題目規定不能使用浮點運算 IP（如 ChipWare、DesignWare）。

## 架構

乘法分成三部分：sign 取 XOR，exponent 相加後減掉 bias（1023），補回 implicit 1 的 53-bit mantissa 相乘。53×53 的乘法拆成 4 個較小的乘法：mantissa 分成上 27 bits、下 26 bits，展開後再分級加總，縮短每一級的路徑。

控制用 FSM 分成 LOAD、COMP、OUT 三個狀態，運算切成以下幾級：

| Stage | 動作 |
| --- | --- |
| C1 | 拆出 sign、exponent、fraction，補回 implicit 1，偵測 Zero、Inf、NaN |
| C2 | 計算 `e_a + e_b − 1023`，mantissa 切成上 27 bits、下 26 bits |
| C3 | 4 個 partial product：27×27、27×26、26×27、26×26 |
| C4 | 兩個交叉項相加：`pp_hl + pp_lh` |
| C5 | 高低位分開相加：`pp_hh` + 交叉項高位、交叉項低位 + `pp_ll` |
| C6 | 合併成 106-bit 乘積並正規化，取出 mantissa、guard bit、sticky bit |
| C7 | Round to nearest even；mantissa 進位溢出時右移一位、exponent 加 1 |
| C8 | 組合邏輯：處理特殊情況，組回 64-bit 結果 |

特殊情況由上往下優先判斷：

| 情況 | 輸出 |
| --- | --- |
| 任一輸入為 NaN，或 Inf × 0 | NaN（`0x7FF8000000000000`） |
| 任一輸入為 Inf | ±Inf |
| 任一輸入為 0 | ±0 |
| 結果 overflow | ±Inf |
| 結果 underflow | ±0（Flush-To-Zero，不產生 subnormal） |

## 驗證

Testbench 用 `$bitstoreal` 把 A、B 轉成 real，由模擬器算出 `A * B`，再用 `$realtobits` 轉回 64 bits 當作期望值，和電路輸出逐筆比對。NaN 只確認兩邊都是 NaN，不比對 sign 和 payload。模擬結束時依錯誤筆數顯示 `Simulation OK!!!!` 或 `Simulation Fail!`。

測資：

- 3 筆固定測資：1.5 × 2.0、−3.14 × 2.5、0.333… × 3.0
- 20 筆隨機測資：`{$random, $random}`
- 6 筆特殊情況：0、Inf、NaN、Inf × 0、最大值 × 2.0（overflow）、最小正規數相乘（underflow）

| Testbench | 階段 | 讀入的設計 |
| --- | --- | --- |
| `TEST_CHIP.v` | RTL 模擬 | `CHIP.v` |
| `TEST_CHIP_gate` | 合成後 gate-level 模擬 | `CHIP_syn.v`、`CHIP.sdf` |
| `TEST_CHIP_post.v` | APR 後 post-layout 模擬 | `../Innovus/CHIP.v`、`../Innovus/CHIP.sdf` |

Gate-level 和 post-layout 的 testbench 會另外輸出 toggle count（`CHIP.tcf`），給功耗分析用。

## 結果

數據取自期末報告。

| 項目 | 數值 |
| --- | --- |
| 操作頻率 | 2.0 GHz（clock period 0.5 ns） |
| 合成 timing slack | 4 ps |
| 合成面積 | 8,145.088 μm² |
| Die size | 133.29 × 131.136 μm |
| Core area | 109.17 × 107.136 ≈ 11,694.4 μm² |
| Post-route WNS（setup / hold） | 0.064 ns / 0.017 ns |
| 總功耗 | 18.09 mW（internal 11.08、switching 4.941、leakage 2.068） |
| IR drop | 最大約 3.71 mV |
| DRC / LVS | 皆通過 |

## 設計流程

製程為 N16ADFP（16 nm），在工作站上完成。`檔案結構/` 是工作站上各資料夾的 `ls` 截圖：

| 資料夾 | 內容 | 工具 |
| --- | --- | --- |
| `RTL/` | RTL 模擬 | NC-Verilog、Verdi |
| `Synthesis/` | 邏輯合成 | Cadence Genus |
| `Netlist/` | Gate-level 與 post-layout 模擬 | NC-Verilog |
| `Innovus/` | APR，功耗與 IR drop 分析 | Cadence Innovus、Voltus |
| `drc/`、`lvs/` | DRC、LVS 檢查 | Calibre |
| `add_dummy/` | 加入 dummy fill | — |
| `virtuoso/` | 檢視 layout | Cadence Virtuoso |

## 檔案

| 檔案 | 說明 |
| --- | --- |
| `CHIP.v` | RTL 設計 |
| `TEST_CHIP.v`、`TEST_CHIP_gate`、`TEST_CHIP_post.v` | 三個階段的 testbench |
| `614410105 劉宇軒 Final Project Report.pdf`（`.docx`） | 期末報告 |
| `final project 報告資料.docx` | 報告用的截圖（timing、IR drop、chip size、DRC、LVS） |
| `檔案結構/` | 工作站資料夾的 `ls` 截圖 |

## 注意事項

- 課程的題目講義版權屬於課程，所以沒有放進 repo。
- 合成與 APR 產生的檔案（netlist、SDF、GDS 等）和製程 library 都留在工作站上，沒有放進 repo，所以 gate-level 和 post-layout 的 testbench 無法單靠這個 repo 執行。`檔案結構/` 裡兩個 `(APR產生).txt` 是空白檔，只用來標示 `CHIP.gds`、`CHIP_LVS.v` 的位置。
- Testbench 用到 `$fsdbDumpfile`（Verdi）和 `$toggle_count`（Cadence 模擬器）。改用其他模擬器時，要先把這幾行拿掉。

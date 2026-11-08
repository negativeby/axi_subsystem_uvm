# AXI4 Subsystem UVM Verification Platform

基于 UVM 1.2 构建的 AXI4 互联子系统验证平台。验证对象包括 2x2 AXI Crossbar（基于 Alex Forencich 开源实现）、32KB AXI RAM、4KB AXI-Lite RAM 以及 AXI-to-AXIL 位宽/协议转换适配桥（axi_axil_adapter）。

---

## 1. 系统架构与内存映射 (Memory Map)

### 拓扑结构
* **Master 0**: AXI4 UVM VIP（作为 CPU Master，驱动 64-bit 全特性读写）
* **Master 1**: AXI4 UVM VIP（模拟硬件 DMA Master，实现双主高频穿插压测）
* **Slave 0**: 32KB AXI RAM（64-bit 数据位宽，支持 INCR / FIXED 突发）
* **Slave 1**: 4KB AXI-Lite RAM（32-bit 数据位宽，经由适配桥完成协议转换与数据拼装）

### 地址分配表
| 地址区间 | 空间大小 | 映射目标 | 预期响应 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `0x0000_0000 - 0x0000_7FFF` | 32KB | Slave 0 (AXI RAM) | `OKAY` (2'b00) | 64-bit 宽总线，支持最大 16 拍突发 |
| `0x0000_8000 - 0x0000_FFFF` | 32KB | 未映射空洞 A | `DECERR` (2'b11) | 默认从机拦截，返回译码错误 |
| `0x0001_0000 - 0x0001_0FFF` | 4KB  | Slave 1 (AXIL RAM) | `OKAY` (2'b00) | 经 Adapter 桥接，仅支持单拍传输 |
| `0x0001_1000 - 0x0001_FFFF` | 60KB | 未映射空洞 B | `DECERR` (2'b11) | 默认从机拦截，返回译码错误 |

---

## 2. 验证进展与测试矩阵

* **Stage 1 [PASSED] `pingpong_test`**：单主单从基础握手打通，验证常规单拍读写与回读比对。
* **Stage 2.1 [PASSED] `adapter_test`**：定向验证 AXI 到 AXI-Lite 的位宽转换，覆盖 64-bit 到 32-bit 的拆包重组、读数据合并与 `RLAST` 补齐（156 拍多长突发对账 0 Mismatch）。
* **Stage 2.2 [PASSED] `decerr_test`**：未映射空洞定向注入，校验 Crossbar 内部默认从机的数据吞噬与状态回执（读写 40/40 笔均准确返回 `DECERR`）。
* **Stage 3 [PASSED] `concurrent_test`**：双 Master 全双工交织压测，验证 Crossbar 内部仲裁流控与资源隔离：
  * **Scoreboard 数据对比**：262 笔事务（共 230 拍有效数据）比对无误，**0 Mismatch**。
  * **功能覆盖率**：AXI4 互联矩阵总覆盖率达 **93.18%**。
  * **路由矩阵覆盖**：`cross_matrix`（Master × Slave × R/W 共 12 组组合）达到 **100%**。
  * **协议断言 (SVA)**：在线集成 Valid-Ready 稳定性、4KB 跨界检测、WLAST-AWLEN 同步共 3 组硬件断言，实现全阶段无违规监控。

---

## 3. 关键缺陷排查与工程记录 (Debug Log)

### 1. Driver 写响应通道（B 通道）采样竞争引发挂死
* **现象**：压测过程中发送少量写事务后，DUT 的 `awready` 持续拉低，仿真在看门狗超时处终止。
* **根因**：`drive_b_channel` 中在同一时钟沿执行了非阻塞赋值覆盖，导致物理接口上的 `bready` 脉冲被吞噬。Crossbar 内部深度为 2 的未决写响应队列无法正常清空，触发上游物理级反压。
* **修复**：重构握手采样逻辑，使用严谨的边缘敏感控制，保证 `bready` 在物理时钟沿维持至少 1 拍稳定电平。

### 2. Monitor 遭遇“W 先于 AW”合法协议乱序误报异常
* **现象**：向空洞地址写数据时，Monitor 抛出 `[MON_W_NO_AW]` 错误，提示收到 W 握手但未决队列中缺少 AW 信息。
* **根因**：AXI 协议明确允许写数据先于写地址到达。当访问未映射地址时，Crossbar 内部 Skid Buffer 快速拉高 `wready` 吸收数据，但地址译码较慢，导致 W 提前 1~2 拍握手。原 Monitor 假定 AW 严格先于 W。
* **修复**：重构写事务组装逻辑，引入独立暂存区暂存先到达的 W 数据拍，待 AW 握手后再完成整笔事务的绑定与传递。

### 3. 突发长度约束位宽截断导致突发压测退化
* **现象**：测试序列配置了 1~16 拍的随机突发，但覆盖率报表中 `long_burst` 和 `med_burst` 采样数恒为 0，突发长度覆盖率停滞在 50%。
* **根因**：4KB 边界裁剪保护中使用了 `12'h1000` 作为上限。Verilog 语法中 12-bit 常量无法表示十进制的 4096，最高位溢出截断后实际等于 `12'h000`。该判断恒为真，导致所有的随机 `rnd_len` 在发送前均被强制清零，突发压测退化为纯单拍传输。
* **修复**：将阈值修改为 `16'h1000` 并结合地址低 12 位精确计算传输跨度，解除异常裁剪，功能覆盖率随后提升至 93.18%。

### 4. 接口层集成 AXI4 协议 SVA 断言集
为避免由于 VIP 自身驱动缺陷引发的假通过，在 `axi_if.sv` 中嵌入硬件断言：
* **Valid-Ready 稳定性**：断言 Valid 置起后在 Ready 握手前 Payload 不发生变化（ARM A2.2.1）。
* **4KB 跨界检查**：断言所有 INCR 突发的地址跨度严禁溢出 `0x1000` 页面边界（ARM A3.4.1）。
* **WLAST 对齐检查**：结合内置 FIFO 动态跟踪事务在飞长度，严格断言最后一拍数据与 `AWLEN` 一致（ARM A3.4.4）。

# AXI4 Subsystem UVM 验证平台

基于 UVM 1.2 搭建的 AXI4 总线子系统验证平台。目标 DUT 包含 2x2 AXI Crossbar（Alex Forencich 开源实现）、32KB AXI RAM、4KB AXI-Lite RAM、位宽适配桥（axi_axil_adapter）以及硬件搬运引擎（axi_dma）。

---

## 1. 总线拓扑与物理地址映射

### 总线拓扑
* Master 0: AXI4 UVM VIP（模拟主处理器，驱动读写）
* Master 1: AXI DMA 引擎（硬件搬运引擎，Stage 3 激活）
* Slave 0: AXI RAM（32KB，64-bit 总线宽，支持 INCR 突发）
* Slave 1: AXI-Lite RAM（4KB，32-bit 总线宽，经由适配桥转换）

### 地址分配表 (Memory Map)
* 0x0000_0000 - 0x0000_7FFF: Slave 0 (32KB AXI RAM), 正常访问返回 OKAY (2'b00)
* 0x0000_8000 - 0x0000_FFFF: 未映射空洞 A (32KB), 预期 Crossbar 返回 DECERR (2'b11)
* 0x0001_0000 - 0x0001_0FFF: Slave 1 (4KB AXI-Lite RAM), 适配桥自动拆包拼装，返回 OKAY (2'b00)
* 0x0001_1000 - 0x0001_FFFF: 未映射空洞 B (60KB), 预期 Crossbar 返回 DECERR (2'b11)

---

## 2. 验证进度与测试矩阵

* Stage 1 [PASSED]: pingpong_test - 基础读写握手打通与单从机乒乓回读
* Stage 2.1 [PASSED]: adapter_test - AXI4 长突发写拆包、AXI-Lite 串行化、读数据拼装及 RLAST 补齐 (156 拍多长突发全部对账成功，0 错拍)
* Stage 2.2 [PASSED]: decerr_test - 地址空洞注入、Crossbar 默认从机数据吞噬与 DECERR 状态码校验 (40/40 笔非法读写均准确回吐 DECERR)
* Stage 3 [WIP]: dma_concurrent_test - VIP 与 DMA 双 Master 竞争、Crossbar 仲裁与交叉路由 (待激活 DMA 描述符控制通道)

---

## 3. 关键缺陷定位与调试记录

1. Driver 写响应通道（B 通道）非阻塞赋值死锁：
   - 现象：异常测试中发完两笔写后 awready 恒为 0，仿真挂死。
   - 根因：drive_b_channel 中在同一时钟沿先后执行 bready <= 1 与 while (!bvalid) 后的 bready <= 0。非阻塞赋值覆盖导致物理引脚未产生有效脉冲。Crossbar 内部深度为 2 的未决写响应队列无法退役，撑爆后对主设备触发物理级反压。
   - 修复：改用标准的 do ... while (vif.bvalid !== 1'b1) 握手采样，保证 bready 在物理时钟沿维持至少 1 拍有效电平。

2. Monitor 对“W 先于 AW”合法总线时序报假错：
   - 现象：空洞地址注入时 Monitor 报 [MON_W_NO_AW] 检测到 W 握手但未决队列中无任何 AW 地址事务。
   - 根因：AXI 规范允许写数据先于写地址握手。面对非法写时，Crossbar 内部 Skid Buffer 快速拉高 wready 吞噬数据，但 awready 因译码慢了 1~2 拍造成 W 抢跑。
   - 修复：在 Monitor 中重构写采样引擎，增加孤儿数据暂存缓冲（pre_w_data / pre_w_strb），在 AW 握手后再完成事务绑定与组装。

3. Scoreboard 未映射地址污染参考模型：
   - 现象：Scoreboard 默认记录所有写事务，写入空洞时污染了 golden_mem，导致后续回读空洞与硬件的 DECERR 产生假不匹配。
   - 修复：在 Scoreboard 内部增加地址译码断言。合法地址校验数据与 OKAY；未映射地址跳过内存更新，严格断言 bresp/rresp === 2'b11。

---

## 4. 仿真运行说明

依赖工具：Synopsys VCS 2018.09 + Verdi，UVM 1.2

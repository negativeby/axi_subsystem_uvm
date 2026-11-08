`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic clk,
    input logic rst_n
);

    // ==========================================
    // 1. 写地址通道 (AW Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    awid;     // 写事务 ID
    logic [ADDR_WIDTH-1:0]  awaddr;   // 起始写地址
    logic [7:0]             awlen;    // 突发拍数 - 1
    logic [2:0]             awsize;   // 每拍字节数 (3'b011 代表 8 字节 = 64位)
    logic [1:0]             awburst;  // 突发类型 (01: INCR 地址递增)
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic                   awvalid;  // 主机发起有效写地址
    logic                   awready;  // 从机准备好接收写地址

    // ==========================================
    // 2. 写数据通道 (W Channel)
    // ==========================================
    logic [DATA_WIDTH-1:0]  wdata;    // 64 位写数据
    logic [STRB_WIDTH-1:0]  wstrb;    // 字节使能 (控制 8 个字节中哪几个有效)
    logic                   wlast;    // 突发最后一拍标志
    logic                   wvalid;   // 主机发出有效数据
    logic                   wready;   // 从机准备好收数据

    // ==========================================
    // 3. 写响应通道 (B Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    bid;      // 返回的写事务 ID
    logic [1:0]             bresp;    // 写状态回执 (00: OKAY, 非0: 出错)
    logic                   bvalid;   // 从机发出写回执
    logic                   bready;   // 主机准备好接收回执

    // ==========================================
    // 4. 读地址通道 (AR Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    arid;     // 读事务 ID
    logic [ADDR_WIDTH-1:0]  araddr;   // 起始读地址
    logic [7:0]             arlen;    // 突发读拍数 - 1
    logic [2:0]             arsize;   // 每拍字节数
    logic [1:0]             arburst;  // 突发类型 (01: INCR)
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic                   arvalid;  // 主机发起有效读请求
    logic                   arready;  // 从机准备好接收读请求

    // ==========================================
    // 5. 读数据通道 (R Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    rid;      // 返回的读事务 ID
    logic [DATA_WIDTH-1:0]  rdata;    // 从机返回的 64 位读数据
    logic [1:0]             rresp;    // 每拍读状态回执
    logic                   rlast;    // 突发读最后一拍标志
    logic                   rvalid;   // 从机送出有效读数据
    logic                   rready;   // 主机准备好接收读数据

    // ==========================================
    // 6. 时钟块 (Clocking Block)
    // ==========================================
    clocking mst_drv_cb @(posedge clk);
        default input #1ps output #100ps;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1ps;
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport mst_drv_mp (clocking mst_drv_cb, input clk, input rst_n);
    modport mon_mp     (clocking mon_cb,     input clk, input rst_n);

    // ==============================================================
    // AXI4 核心协议 SVA 在线断言集
    // ==============================================================

    // --------------------------------------------------------------
    // 断言 1: Valid-Ready 握手稳定性断言
    // --------------------------------------------------------------
    property p_aw_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> (awvalid && $stable({awaddr, awlen, awsize, awburst, awid}));
    endproperty
    assert_aw_valid_stable: assert property (p_aw_valid_stable)
        else `uvm_error("SVA_AW_STABLE", "AWVALID 置起但 AWREADY 为低时，AW 通道信号发生非法跳变！")

    property p_w_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> (wvalid && $stable({wdata, wstrb, wlast}));
    endproperty
    assert_w_valid_stable: assert property (p_w_valid_stable)
        else `uvm_error("SVA_W_STABLE", "WVALID 置起但 WREADY 为低时，W 通道数据/掩码/WLAST 发生非法跳变！")

    property p_ar_valid_stable;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> (arvalid && $stable({araddr, arlen, arsize, arburst, arid}));
    endproperty
    assert_ar_valid_stable: assert property (p_ar_valid_stable)
        else `uvm_error("SVA_AR_STABLE", "ARVALID 置起但 ARREADY 为低时，AR 通道信号发生非法跳变！")

    // --------------------------------------------------------------
    // 断言 2: 4KB 边界跨越违规检测 
    // --------------------------------------------------------------
    property p_aw_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && awready && awburst == 2'b01) |-> (((awaddr & 12'hFFF) + ((awlen + 1) << awsize)) <= 13'h1000);
    endproperty
    assert_aw_4kb_boundary: assert property (p_aw_4kb_boundary)
        else `uvm_error("SVA_AW_4KB", $sformatf("AW 突发写跨越 4KB 边界! addr=0x%08x, len=%0d, size=%0d", awaddr, awlen, awsize))

    property p_ar_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && arready && arburst == 2'b01) |-> (((araddr & 12'hFFF) + ((arlen + 1) << arsize)) <= 13'h1000);
    endproperty
    assert_ar_4kb_boundary: assert property (p_ar_4kb_boundary)
        else `uvm_error("SVA_AR_4KB", $sformatf("AR 突发读跨越 4KB 边界! addr=0x%08x, len=%0d, size=%0d", araddr, arlen, arsize))

    // --------------------------------------------------------------
    // 断言 3: WLAST 与 AWLEN 严格对齐断言 (A3.4.4 规则)
    // --------------------------------------------------------------
    int unsigned w_beat_cnt = 0;
    bit [7:0]    awlen_fifo[$];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awlen_fifo.delete();
            w_beat_cnt <= 0;
        end else begin
            if (awvalid && awready) begin
                awlen_fifo.push_back(awlen);
            end

            if (wvalid && wready) begin
                bit [7:0] active_len;
                if (awlen_fifo.size() == 0 && awvalid && awready) begin
                    active_len = awlen;
                end else if (awlen_fifo.size() > 0) begin
                    active_len = awlen_fifo[0];
                end else begin
                    active_len = 8'd0;
                end

                if (wlast) begin
                    assert_wlast_exact: assert (w_beat_cnt == active_len)
                        else `uvm_error("SVA_WLAST_MISMATCH", $sformatf("WLAST 提前或滞后触发! 当前拍数=%0d, 预期长度=%0d", w_beat_cnt, active_len));

                    w_beat_cnt <= 0;
                    if (awlen_fifo.size() > 0) begin
                        void'(awlen_fifo.pop_front());
                    end
                end else begin
                    assert_wlast_not_premature: assert (w_beat_cnt < active_len)
                        else `uvm_error("SVA_WLAST_MISSING", $sformatf("W 拍数已达 %0d，但 WLAST 未置高!", w_beat_cnt));
                    w_beat_cnt <= w_beat_cnt + 1;
                end
            end
        end
    end

endinterface: axi_if

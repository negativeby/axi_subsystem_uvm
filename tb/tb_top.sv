`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

module tb_top;

    // ==============================================================
    // 1. 全局时钟与复位生成 (100MHz: 周期 10ns)
    // ==============================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 每 5ns 翻转一次，生成 100MHz 稳定时钟
    end

    initial begin
        rst_n = 1'b0;          // 开机保持复位有效 (低电平)
        #100;                  // 维持复位 100ns
        @(posedge clk);
        rst_n = 1'b1;          // 释放复位
        `uvm_info("TB_TOP", "系统复位释放，时钟与电源网络就绪！", UVM_LOW)
    end

    // ==============================================================
    // 2. 例化物理 AXI4 接口 (axi_if)
    // ==============================================================
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;
    localparam ID_WIDTH   = 8;
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) axi_vif (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // ==============================================================
    // 3. 例化待测子系统 (subsystem_top)，完成引脚互联
    // ==============================================================
    subsystem_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),

        // AXI4 写地址通道 (AW)
        .s_axi_awid          (axi_vif.awid),
        .s_axi_awaddr        (axi_vif.awaddr),
        .s_axi_awlen         (axi_vif.awlen),
        .s_axi_awsize        (axi_vif.awsize),
        .s_axi_awburst       (axi_vif.awburst),
        .s_axi_awlock        (axi_vif.awlock),
        .s_axi_awcache       (axi_vif.awcache),
        .s_axi_awprot        (axi_vif.awprot),
        .s_axi_awvalid       (axi_vif.awvalid),
        .s_axi_awready       (axi_vif.awready),

        // AXI4 写数据通道 (W)
        .s_axi_wdata         (axi_vif.wdata),
        .s_axi_wstrb         (axi_vif.wstrb),
        .s_axi_wlast         (axi_vif.wlast),
        .s_axi_wvalid        (axi_vif.wvalid),
        .s_axi_wready        (axi_vif.wready),

        // AXI4 写响应通道 (B)
        .s_axi_bid           (axi_vif.bid),
        .s_axi_bresp         (axi_vif.bresp),
        .s_axi_bvalid        (axi_vif.bvalid),
        .s_axi_bready        (axi_vif.bready),

        // AXI4 读地址通道 (AR)
        .s_axi_arid          (axi_vif.arid),
        .s_axi_araddr        (axi_vif.araddr),
        .s_axi_arlen         (axi_vif.arlen),
        .s_axi_arsize        (axi_vif.arsize),
        .s_axi_arburst       (axi_vif.arburst),
        .s_axi_arlock        (axi_vif.arlock),
        .s_axi_arcache       (axi_vif.arcache),
        .s_axi_arprot        (axi_vif.arprot),
        .s_axi_arvalid       (axi_vif.arvalid),
        .s_axi_arready       (axi_vif.arready),

        // AXI4 读数据通道 (R)
        .s_axi_rid           (axi_vif.rid),
        .s_axi_rdata         (axi_vif.rdata),
        .s_axi_rresp         (axi_vif.rresp),
        .s_axi_rlast         (axi_vif.rlast),
        .s_axi_rvalid        (axi_vif.rvalid),
        .s_axi_rready        (axi_vif.rready),

        // DMA 控制流通道 (先接低电平闲置，后续测试 DMA 时接专用通道)
        .dma_read_desc_addr  (32'h0),
        .dma_read_desc_len   (16'h0),
        .dma_read_desc_tag   (8'h0),
        .dma_read_desc_valid (1'b0),
        .dma_read_desc_ready (),

        .dma_write_desc_addr (32'h0),
        .dma_write_desc_len  (16'h0),
        .dma_write_desc_tag  (8'h0),
        .dma_write_desc_valid(1'b0),
        .dma_write_desc_ready()
    );

    // ==============================================================
    // 4. UVM 接口配置与 Verdi 波形转储
    // ==============================================================
    initial begin
        // 将物理接口放入 UVM 配置数据库，广播给全局所有的 UVM 组件 (Driver, Monitor)
        uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::set(
            null, "*", "vif", axi_vif
        );

        // 配置 Verdi 专用的 FSDB 波形转储
        $fsdbDumpfile("tb_top.fsdb");
        $fsdbDumpvars(0, tb_top);
        $fsdbDumpMDA(); // 转储多维数组与内部 RAM 内容

        // 启动 UVM 测试用例引导流程
        run_test();
    end

endmodule: tb_top

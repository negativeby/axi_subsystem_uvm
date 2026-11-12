`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

module tb_top;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;
    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam ID_WIDTH   = 8;

    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #105ns;
        rst_n = 1'b1;
        `uvm_info("TB_TOP", "系统复位释放，双主总线验证平台启动！", UVM_LOW)
    end

    // Master 0 VIP 物理接口
    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) axi_vif0 (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // Master 1 VIP 物理接口
    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) axi_vif1 (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // DUT 实例化
    subsystem_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),

        // Master 0 接入
        .s0_axi_awid   (axi_vif0.awid),
        .s0_axi_awaddr (axi_vif0.awaddr),
        .s0_axi_awlen  (axi_vif0.awlen),
        .s0_axi_awsize (axi_vif0.awsize),
        .s0_axi_awburst(axi_vif0.awburst),
        .s0_axi_awlock (axi_vif0.awlock),
        .s0_axi_awcache(axi_vif0.awcache),
        .s0_axi_awprot (axi_vif0.awprot),
        .s0_axi_awvalid(axi_vif0.awvalid),
        .s0_axi_awready(axi_vif0.awready),
        .s0_axi_wdata  (axi_vif0.wdata),
        .s0_axi_wstrb  (axi_vif0.wstrb),
        .s0_axi_wlast  (axi_vif0.wlast),
        .s0_axi_wvalid (axi_vif0.wvalid),
        .s0_axi_wready (axi_vif0.wready),
        .s0_axi_bid    (axi_vif0.bid),
        .s0_axi_bresp  (axi_vif0.bresp),
        .s0_axi_bvalid (axi_vif0.bvalid),
        .s0_axi_bready (axi_vif0.bready),
        .s0_axi_arid   (axi_vif0.arid),
        .s0_axi_araddr (axi_vif0.araddr),
        .s0_axi_arlen  (axi_vif0.arlen),
        .s0_axi_arsize (axi_vif0.arsize),
        .s0_axi_arburst(axi_vif0.arburst),
        .s0_axi_arlock (axi_vif0.arlock),
        .s0_axi_arcache(axi_vif0.arcache),
        .s0_axi_arprot (axi_vif0.arprot),
        .s0_axi_arvalid(axi_vif0.arvalid),
        .s0_axi_arready(axi_vif0.arready),
        .s0_axi_rid    (axi_vif0.rid),
        .s0_axi_rdata  (axi_vif0.rdata),
        .s0_axi_rresp  (axi_vif0.rresp),
        .s0_axi_rlast  (axi_vif0.rlast),
        .s0_axi_rvalid (axi_vif0.rvalid),
        .s0_axi_rready (axi_vif0.rready),

        // Master 1 接入
        .s1_axi_awid   (axi_vif1.awid),
        .s1_axi_awaddr (axi_vif1.awaddr),
        .s1_axi_awlen  (axi_vif1.awlen),
        .s1_axi_awsize (axi_vif1.awsize),
        .s1_axi_awburst(axi_vif1.awburst),
        .s1_axi_awlock (axi_vif1.awlock),
        .s1_axi_awcache(axi_vif1.awcache),
        .s1_axi_awprot (axi_vif1.awprot),
        .s1_axi_awvalid(axi_vif1.awvalid),
        .s1_axi_awready(axi_vif1.awready),
        .s1_axi_wdata  (axi_vif1.wdata),
        .s1_axi_wstrb  (axi_vif1.wstrb),
        .s1_axi_wlast  (axi_vif1.wlast),
        .s1_axi_wvalid (axi_vif1.wvalid),
        .s1_axi_wready (axi_vif1.wready),
        .s1_axi_bid    (axi_vif1.bid),
        .s1_axi_bresp  (axi_vif1.bresp),
        .s1_axi_bvalid (axi_vif1.bvalid),
        .s1_axi_bready (axi_vif1.bready),
        .s1_axi_arid   (axi_vif1.arid),
        .s1_axi_araddr (axi_vif1.araddr),
        .s1_axi_arlen  (axi_vif1.arlen),
        .s1_axi_arsize (axi_vif1.arsize),
        .s1_axi_arburst(axi_vif1.arburst),
        .s1_axi_arlock (axi_vif1.arlock),
        .s1_axi_arcache(axi_vif1.arcache),
        .s1_axi_arprot (axi_vif1.arprot),
        .s1_axi_arvalid(axi_vif1.arvalid),
        .s1_axi_arready(axi_vif1.arready),
        .s1_axi_rid    (axi_vif1.rid),
        .s1_axi_rdata  (axi_vif1.rdata),
        .s1_axi_rresp  (axi_vif1.rresp),
        .s1_axi_rlast  (axi_vif1.rlast),
        .s1_axi_rvalid (axi_vif1.rvalid),
        .s1_axi_rready (axi_vif1.rready)
    );

    initial begin
        $fsdbDumpfile("tb_top.fsdb");
        $fsdbDumpvars(0, tb_top, "+all", "+mda");

        // 分别配置 Master 0 和 Master 1 的虚接口
        uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::set(
            null, "*.m0_agent.*", "vif", axi_vif0
        );
        uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::set(
            null, "*.m1_agent.*", "vif", axi_vif1
        );
        uvm_config_db#(virtual axi_if#(32, 64, 8))::set(null, "*", "vif_m0",        axi_vif0);
    uvm_config_db#(virtual axi_if#(32, 64, 8))::set(null, "*", "vif_m1", axi_vif1);

        run_test();
    end

    // 硬看门狗超时保护 
    initial begin
        #500000000ns;
        $display("[HARDWARE_WATCHDOG] 仿真到达 500000000ns 保护上限，强制退出！");
        $finish;
    end

endmodule

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_driver #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_driver #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // 虚拟接口指针，通过 config_db 从顶层获取
    virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) vif;

    // UVM 工厂注册
    `uvm_component_param_utils(axi_driver #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 从配置数据库中获取由 tb_top 广播的 vif 指针
        if (!uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        // 1. 系统复位期：初始化总线控制信号为低电平
        reset_signals();

        // 2. 等待复位释放
        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        `uvm_info("AXI_DRV", "Driver 检测到复位已释放，进入工作就绪状态", UVM_MEDIUM)

        // 3. 循环从 Sequencer 获取事务并驱动
        forever begin
            seq_item_port.get_next_item(req);
            drive_transfer(req);
            seq_item_port.item_done();
        end
    endtask: run_phase

    // 信号复位初态管理
    virtual task reset_signals();
        vif.awvalid <= 1'b0;
        vif.awid    <= '0;
        vif.awaddr  <= '0;
        vif.awlen   <= '0;
        vif.awsize  <= '0;
        vif.awburst <= '0;
        vif.awlock  <= '0;
        vif.awcache <= '0;
        vif.awprot  <= '0;

        vif.wvalid  <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wlast   <= 1'b0;

        vif.bready  <= 1'b0;

        vif.arvalid <= 1'b0;
        vif.arid    <= '0;
        vif.araddr  <= '0;
        vif.arlen   <= '0;
        vif.arsize  <= '0;
        vif.arburst <= '0;
        vif.arlock  <= '0;
        vif.arcache <= '0;
        vif.arprot  <= '0;

        vif.rready  <= 1'b0;
    endtask: reset_signals

    // 核心事务分流
    virtual task drive_transfer(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        if (tr.trans_type == AXI_WRITE) begin
            drive_write(tr);
        end else begin
            drive_read(tr);
        end
    endtask: drive_transfer

    // ==============================================================
    // 写事务驱动实现 (AW, W 并发驱动 -> 收集 B 响应)
    // ==============================================================
    virtual task drive_write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        fork
            drive_aw_channel(tr);
            drive_w_channel(tr);
        join
        drive_b_channel(tr);
    endtask: drive_write

    // 写地址通道 (AW)
    virtual task drive_aw_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        @(posedge vif.clk);
        vif.awid    <= tr.id;
        vif.awaddr  <= tr.addr;
        vif.awlen   <= tr.len;
        vif.awsize  <= tr.size;
        vif.awburst <= tr.burst;
        vif.awlock  <= tr.lock;
        vif.awcache <= tr.cache;
        vif.awprot  <= tr.prot;
        vif.awvalid <= 1'b1;

        // 持续保持 valid 直到 slave 拉高 ready 完成握手
        do begin
            @(posedge vif.clk);
        end while (!vif.awready);

        // 握手成功，撤销 valid
        vif.awvalid <= 1'b0;
    endtask: drive_aw_channel

    // 写数据通道 (W)
virtual task drive_w_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
    int unsigned total_beats = tr.len + 1;

    for (int i = 0; i < total_beats; i++) begin
        // 1. 无缝打上当前拍的数据和控制信号
        vif.wdata  <= tr.data[i];
        vif.wstrb  <= (i < tr.strb.size()) ? tr.strb[i] : {STRB_WIDTH{1'b1}};
        vif.wlast  <= (i == total_beats - 1) ? 1'b1 : 1'b0;
        vif.wvalid <= 1'b1;

        // 2. 严格等待本拍的握手成立 (时钟上升沿且 wready 为高)
        do begin
            @(posedge vif.clk);
        end while (!vif.wready);
    end

    // 传输全部完成后撤销信号
    vif.wvalid <= 1'b0;
    vif.wlast  <= 1'b0;
endtask: drive_w_channel

    // 写响应通道 (B)
    virtual task drive_b_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        @(posedge vif.clk);
        vif.bready <= 1'b1; // Master 准备好接收响应

        // 等待从机返回 bvalid
        while (!vif.bvalid) begin
            @(posedge vif.clk);
        end

        // 握手成功，记录响应状态并撤销 bready
        tr.bresp = vif.bresp;
        vif.bready <= 1'b0;
    endtask: drive_b_channel

    // ==============================================================
    // 读事务驱动实现 (发起 AR -> 循环接收 R 数据直至 RLAST)
    // ==============================================================
    virtual task drive_read(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        // 1. 发起读地址通道握手
        @(posedge vif.clk);
        vif.arid    <= tr.id;
        vif.araddr  <= tr.addr;
        vif.arlen   <= tr.len;
        vif.arsize  <= tr.size;
        vif.arburst <= tr.burst;
        vif.arlock  <= tr.lock;
        vif.arcache <= tr.cache;
        vif.arprot  <= tr.prot;
        vif.arvalid <= 1'b1;

        do begin
            @(posedge vif.clk);
        end while (!vif.arready);

        vif.arvalid <= 1'b0;

        // 2. 接收读数据流
        tr.data.delete();
        while (1) begin
            @(posedge vif.clk);
            vif.rready <= 1'b1; // 接收就绪

            if (vif.rvalid && vif.rready) begin
                tr.data.push_back(vif.rdata);
                tr.rresp = vif.rresp;
                if (vif.rlast) begin
                    break;
                end
            end
        end

        vif.rready <= 1'b0;
    endtask: drive_read

endclass: axi_driver

`endif // AXI_DRIVER_SV

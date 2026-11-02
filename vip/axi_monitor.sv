`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_monitor #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_monitor;

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // 虚拟接口指针
    virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) vif;

    // TLM 广播端口：将采集到的完整 AXI 事务发送给 Scoreboard 与 Coverage
    uvm_analysis_port #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)) item_collected_port;

    `uvm_component_param_utils(axi_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        // 等待系统复位释放
        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        `uvm_info("AXI_MON", "Monitor 监测到系统复位释放，启动总线被动采样", UVM_MEDIUM)

        // 读通道和写通道在硬件上完全独立，启动两个并行的监听进程
        fork
            collect_write_trans();
            collect_read_trans();
        join
    endtask: run_phase

    // ==============================================================
    // 写通道采样线程：AW -> W(直到 WLAST) -> B
    // ==============================================================
    virtual task collect_write_trans();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;

        forever begin
            tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_wr_tr");
            tr.trans_type = AXI_WRITE;

            // AW 与 W 通道物理解耦，使用 fork...join 并发捕获
            fork
                begin
                    do begin
                        @(posedge vif.clk);
                    end while (!(vif.awvalid === 1'b1 && vif.awready === 1'b1));

                    tr.id    = vif.awid;
                    tr.addr  = vif.awaddr;
                    tr.len   = vif.awlen;
                    tr.size  = vif.awsize;
                    tr.burst = vif.awburst;
                    tr.lock  = vif.awlock;
                    tr.cache = vif.awcache;
                    tr.prot  = vif.awprot;
                end
                begin
                    while (1) begin
                        @(posedge vif.clk);
                        if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
                            tr.data.push_back(vif.wdata);
                            tr.strb.push_back(vif.wstrb);
                            if (vif.wlast === 1'b1) begin
                                break;
                            end
                        end
                    end
                end
            join

            // 等待 B 通道写响应
            do begin
                @(posedge vif.clk);
            end while (!(vif.bvalid === 1'b1 && vif.bready === 1'b1));

            tr.bresp = vif.bresp;

            // 广播完整事务
            item_collected_port.write(tr);
        end
    endtask: collect_write_trans

    // ==============================================================
    // 读通道采样线程：AR -> R(直到 RLAST)
    // ==============================================================
    virtual task collect_read_trans();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;

        forever begin
            tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_rd_tr");
            tr.trans_type = AXI_READ;

            // 1. 监测读地址握手 (ARVALID & ARREADY 同时有效)
            do begin
                @(posedge vif.clk);
            end while (!(vif.arvalid === 1'b1 && vif.arready === 1'b1));

            tr.id    = vif.arid;
            tr.addr  = vif.araddr;
            tr.len   = vif.arlen;
            tr.size  = vif.arsize;
            tr.burst = vif.arburst;
            tr.lock  = vif.arlock;
            tr.cache = vif.arcache;
            tr.prot  = vif.arprot;

            // 2. 连续收集读数据拍 (RVALID & RREADY 同时有效)
            while (1) begin
                @(posedge vif.clk);
                if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
                    tr.data.push_back(vif.rdata);
                    tr.rresp = vif.rresp;
                    if (vif.rlast === 1'b1) begin
                        break; // 最后一拍读数据采集完毕
                    end
                end
            end

            // 3. 将完整读事务广播发送
            item_collected_port.write(tr);
        end
    endtask: collect_read_trans

endclass: axi_monitor

`endif // AXI_MONITOR_SV

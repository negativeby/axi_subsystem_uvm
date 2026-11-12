`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_monitor #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8
) extends uvm_monitor;

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) vif;

    uvm_analysis_port #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)) item_collected_port;

    // 写事务三通道全解耦追踪结构：支持 AW / W / B 任意先后到达顺序
    typedef struct {
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;
        bit aw_done;
        bit w_done;
        bit b_done;
    } wr_mon_entry_t;

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

        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        `uvm_info("AXI_MON", "Monitor 启动：支持 AW/W/B 三通道任意到达序与多在途乱序采样", UVM_LOW)

        fork
            collect_write_trans();
            collect_read_trans();
        join
    endtask: run_phase

    // ==============================================================
    // 写通道采样引擎: 基于 (aw_done, w_done, b_done) 三标志对称核销表
    // 完美兼容 AW->W->B、W->AW->B 以及 DECERR 下的 AW->B->W 时序
    // ==============================================================
    virtual task collect_write_trans();
        wr_mon_entry_t wr_inflight_q[$];
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_w_pkt = null;

        forever begin
            @(posedge vif.clk);

            // 1. 采样 AW 握手：匹配已提前到达的 W 项，或新建在途表项
            if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
                int idx = -1;
                for (int i = 0; i < wr_inflight_q.size(); i++) begin
                    if (!wr_inflight_q[i].aw_done) begin
                        idx = i;
                        break;
                    end
                end

                if (idx != -1) begin
                    wr_inflight_q[idx].tr.id    = vif.awid;
                    wr_inflight_q[idx].tr.addr  = vif.awaddr;
                    wr_inflight_q[idx].tr.len   = vif.awlen;
                    wr_inflight_q[idx].tr.size  = vif.awsize;
                    wr_inflight_q[idx].tr.burst = vif.awburst;
                    wr_inflight_q[idx].tr.lock  = vif.awlock;
                    wr_inflight_q[idx].tr.cache = vif.awcache;
                    wr_inflight_q[idx].tr.prot  = vif.awprot;
                    wr_inflight_q[idx].aw_done  = 1'b1;
                end else begin
                    wr_mon_entry_t new_entry;
                    new_entry.tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_wr_tr");
                    new_entry.tr.trans_type = AXI_WRITE;
                    new_entry.tr.id    = vif.awid;
                    new_entry.tr.addr  = vif.awaddr;
                    new_entry.tr.len   = vif.awlen;
                    new_entry.tr.size  = vif.awsize;
                    new_entry.tr.burst = vif.awburst;
                    new_entry.tr.lock  = vif.awlock;
                    new_entry.tr.cache = vif.awcache;
                    new_entry.tr.prot  = vif.awprot;
                    new_entry.aw_done  = 1'b1;
                    new_entry.w_done   = 1'b0;
                    new_entry.b_done   = 1'b0;
                    wr_inflight_q.push_back(new_entry);
                end
            end

            // 2. 采样 W 握手：收集突发数据拍，在 wlast 处挂入首个未完成 W 的表项
            if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
                if (cur_w_pkt == null) begin
                    cur_w_pkt = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("w_pkt");
                end
                cur_w_pkt.data.push_back(vif.wdata);
                cur_w_pkt.strb.push_back(vif.wstrb);

                if (vif.wlast === 1'b1) begin
                    int idx = -1;
                    for (int i = 0; i < wr_inflight_q.size(); i++) begin
                        if (!wr_inflight_q[i].w_done) begin
                            idx = i;
                            break;
                        end
                    end

                    if (idx != -1) begin
                        wr_inflight_q[idx].tr.data = cur_w_pkt.data;
                        wr_inflight_q[idx].tr.strb = cur_w_pkt.strb;
                        wr_inflight_q[idx].w_done  = 1'b1;
                    end else begin
                        wr_mon_entry_t new_entry;
                        new_entry.tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_wr_tr");
                        new_entry.tr.trans_type = AXI_WRITE;
                        new_entry.tr.data = cur_w_pkt.data;
                        new_entry.tr.strb = cur_w_pkt.strb;
                        new_entry.aw_done = 1'b0;
                        new_entry.w_done  = 1'b1;
                        new_entry.b_done  = 1'b0;
                        wr_inflight_q.push_back(new_entry);
                    end
                    cur_w_pkt = null;
                end
            end

            // 3. 采样 B 握手：只要 AW 已建账 (aw_done==1) 且 ID 匹配，即可记录响应
            if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
                int match_idx = -1;
                for (int i = 0; i < wr_inflight_q.size(); i++) begin
                    if (wr_inflight_q[i].aw_done && !wr_inflight_q[i].b_done && (wr_inflight_q[i].tr.id == vif.bid)) begin
                        match_idx = i;
                        break;
                    end
                end

                if (match_idx == -1) begin
                    `uvm_error("MON_B_ORPHAN", $sformatf("收到未匹配写事务的孤儿响应！BID=0x%02x, BRESP=0x%0x (在途表深度=%0d) | 当前AW总线: awvalid=%0b, awready=%0b, awid=0x%02x, awaddr=0x%08x",
                               vif.bid, vif.bresp, wr_inflight_q.size(), vif.awvalid, vif.awready, vif.awid, vif.awaddr))
                    for (int k = 0; k < wr_inflight_q.size(); k++) begin
                        `uvm_info("MON_B_SNAP", $sformatf("  -> 在途表[%0d]: ID=0x%02x, Addr=0x%08x, aw_done=%0b, w_done=%0b, b_done=%0b",
                                  k, wr_inflight_q[k].tr.id, wr_inflight_q[k].tr.addr,
                                  wr_inflight_q[k].aw_done, wr_inflight_q[k].w_done, wr_inflight_q[k].b_done), UVM_LOW)
                    end
                end else begin
                    wr_inflight_q[match_idx].tr.bresp = vif.bresp;
                    wr_inflight_q[match_idx].b_done   = 1'b1;
                end
            end // <--- 之前漏掉的闭合 if (vif.bvalid && vif.bready) 的 end

            // 4. 核销退休：将 aw_done、w_done、b_done 全部就绪的事务广播至 Scoreboard 与 Coverage
            begin
                int i = 0;
                while (i < wr_inflight_q.size()) begin
                    if (wr_inflight_q[i].aw_done && wr_inflight_q[i].w_done && wr_inflight_q[i].b_done) begin
                        item_collected_port.write(wr_inflight_q[i].tr);
                        wr_inflight_q.delete(i);
                    end else begin
                        i++;
                    end
                end
            end
        end
    endtask: collect_write_trans

    // ==============================================================
    // 读通道采样引擎: 支持多 Outstanding 与跨从机乱序返回
    // ==============================================================
    virtual task collect_read_trans();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) ar_pending_q[$];
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) ar_tr;
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_rd_tr;

        forever begin
            @(posedge vif.clk);

            // 1. 采样 AR 握手
            if (vif.arvalid === 1'b1 && vif.arready === 1'b1) begin
                ar_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_rd_tr");
                ar_tr.trans_type = AXI_READ;
                ar_tr.id    = vif.arid;
                ar_tr.addr  = vif.araddr;
                ar_tr.len   = vif.arlen;
                ar_tr.size  = vif.arsize;
                ar_tr.burst = vif.arburst;
                ar_tr.lock  = vif.arlock;
                ar_tr.cache = vif.arcache;
                ar_tr.prot  = vif.arprot;
                ar_pending_q.push_back(ar_tr);
            end

            // 2. 采样 R 握手
            if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
                int match_idx = -1;
                for (int i = 0; i < ar_pending_q.size(); i++) begin
                    if (ar_pending_q[i].id == vif.rid) begin
                        match_idx = i;
                        break;
                    end
                end

                if (match_idx == -1) begin
                    `uvm_error("MON_R_ORPHAN", $sformatf("收到未匹配 AR 地址的孤儿读数据！RID=0x%0h", vif.rid))
                end else begin
                    cur_rd_tr = ar_pending_q[match_idx];
                    cur_rd_tr.data.push_back(vif.rdata);
                    cur_rd_tr.rresp = vif.rresp;

                    if (vif.rlast === 1'b1) begin
                        ar_pending_q.delete(match_idx);
                        item_collected_port.write(cur_rd_tr);
                    end
                end
            end
        end
    endtask: collect_read_trans

endclass: axi_monitor

`endif // AXI_MONITOR_SV

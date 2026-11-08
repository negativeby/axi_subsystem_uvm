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
        `uvm_info("AXI_MON", "Monitor 检测到复位释放，启动多 Outstanding 异步流水采样引擎", UVM_MEDIUM)

        fork
            collect_write_trans();
            collect_read_trans();
        join
    endtask: run_phase

    // ==============================================================
    // 写通道采样引擎: 完整支持 AW 与 W 任意顺序到达 (W-before-AW)
    // ==============================================================
    virtual task collect_write_trans();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) aw_pending_q[$];
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) b_pending_q[$];
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) aw_tr;
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_w_tr;

        // 抢跑缓冲: 暂存先于 AW 到达的 W 数据流
        bit [DATA_WIDTH-1:0] pre_w_data[$];
        bit [STRB_WIDTH-1:0] pre_w_strb[$];
        bit                  pre_w_last_seen = 1'b0;

        forever begin
            @(posedge vif.clk);

            // 1. 采样 AW 握手
            if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
                aw_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon_wr_tr");
                aw_tr.trans_type = AXI_WRITE;
                aw_tr.id    = vif.awid;
                aw_tr.addr  = vif.awaddr;
                aw_tr.len   = vif.awlen;
                aw_tr.size  = vif.awsize;
                aw_tr.burst = vif.awburst;
                aw_tr.lock  = vif.awlock;
                aw_tr.cache = vif.awcache;
                aw_tr.prot  = vif.awprot;

                // 若之前已有数据拍抢跑握手，合并数据
                if (pre_w_data.size() > 0) begin
                    aw_tr.data = pre_w_data;
                    aw_tr.strb = pre_w_strb;
                    pre_w_data.delete();
                    pre_w_strb.delete();

                    if (pre_w_last_seen) begin
                        pre_w_last_seen = 1'b0;
                        b_pending_q.push_back(aw_tr); // 数据已全收齐，直接转入待响应队列
                    end else begin
                        aw_pending_q.push_back(aw_tr); // 尚有后续数据拍未完，入队继续等待
                    end
                end else begin
                    aw_pending_q.push_back(aw_tr);
                end
            end

            // 2. 采样 W 握手
            if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
                if (aw_pending_q.size() > 0) begin
                    cur_w_tr = aw_pending_q[0];
                    cur_w_tr.data.push_back(vif.wdata);
                    cur_w_tr.strb.push_back(vif.wstrb);

                    if (vif.wlast === 1'b1) begin
                        void'(aw_pending_q.pop_front());
                        b_pending_q.push_back(cur_w_tr);
                    end
                end else begin
                    // AW 尚未握手，存入抢跑缓冲
                    pre_w_data.push_back(vif.wdata);
                    pre_w_strb.push_back(vif.wstrb);
                    if (vif.wlast === 1'b1) begin
                        pre_w_last_seen = 1'b1;
                    end
                end
            end

            // 3. 采样 B 握手
            if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
                int match_idx = -1;
                for (int i = 0; i < b_pending_q.size(); i++) begin
                    if (b_pending_q[i].id == vif.bid) begin
                        match_idx = i;
                        break;
                    end
                end

                if (match_idx == -1) begin
                    `uvm_error("MON_B_ORPHAN", $sformatf("收到未匹配写事务的孤儿响应！BID=0x%0h", vif.bid))
                end else begin
                    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) b_tr = b_pending_q[match_idx];
                    b_tr.bresp = vif.bresp;
                    b_pending_q.delete(match_idx);
                    item_collected_port.write(b_tr);
                end
            end
        end
    endtask: collect_write_trans

    // ==============================================================
    // 读通道采样引擎
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

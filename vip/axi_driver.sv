`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_driver #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8
) extends uvm_driver #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) vif;

    // 待派发事务队列
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_q[$];
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_q[$];

    // 在途未决队列 (等待 B 或 R 响应)
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_in_flight_q[$];
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_in_flight_q[$];

    localparam int MAX_QUEUE_DEPTH = 12;

    `uvm_component_param_utils(axi_driver #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);

        reset_signals();

        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        `uvm_info("AXI_DRV", "Driver 启动：多在途读写流水线 + 阵发性拥塞反压引擎就绪", UVM_LOW)

        fork
            fetch_items_process();
            write_worker_process(); // 驱动 AW/W 偏斜并发，不等待 B 响应直接连发下一笔
            b_worker_process();     // 独立监听 B 通道，注入随机反压与拥塞窗口
            ar_worker_process();    // 独立连发 AR 地址
            r_worker_process();     // 独立监听 R 通道，注入随机反压与拥塞窗口
        join
    endtask: run_phase

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

    virtual task fetch_items_process();
        forever begin
            seq_item_port.get_next_item(req);

            if (req.trans_type == AXI_WRITE) begin
                wait(wr_q.size() < MAX_QUEUE_DEPTH);
                wr_q.push_back(req);
            end else begin
                wait(rd_q.size() < MAX_QUEUE_DEPTH);
                rd_q.push_back(req);
            end

            seq_item_port.item_done();
        end
    endtask: fetch_items_process

    // 写发射引擎：保证单笔事务内 AW 与 W 自由偏斜交织，且不会跨事务倒置 W 顺序
    virtual task write_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;
        forever begin
            wait(wr_q.size() > 0 && wr_in_flight_q.size() < MAX_QUEUE_DEPTH);
            tr = wr_q.pop_front();

            // 在开始驱动当前事务时挂入在途队列
            wr_in_flight_q.push_back(tr);

            fork
                begin
                    repeat (tr.aw_delay) @(posedge vif.clk);
                    drive_aw_channel(tr);
                end
                begin
                    repeat (tr.w_delay) @(posedge vif.clk);
                    drive_w_channel(tr);
                end
            join
        end
    endtask: write_worker_process

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

        fork
            begin
                do begin
                    @(posedge vif.clk);
                end while (!vif.awready);
            end
            begin
                repeat (50000) @(posedge vif.clk);
                `uvm_error("DRV_TIMEOUT", $sformatf("AW channel ready timeout! addr=0x%08x", tr.addr))
            end
        join_any
        disable fork;

        vif.awvalid <= 1'b0;
    endtask: drive_aw_channel

    virtual task drive_w_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        int unsigned total_beats = tr.len + 1;
        @(posedge vif.clk);

        for (int i = 0; i < total_beats; i++) begin
            if (tr.w_insert_bubble && (i > 0) && ($urandom_range(0, 99) < 30)) begin
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
                repeat ($urandom_range(1, 2)) @(posedge vif.clk);
            end

            vif.wdata  <= tr.data[i];
            vif.wstrb  <= (i < tr.strb.size()) ? tr.strb[i] : {STRB_WIDTH{1'b1}};
            vif.wlast  <= (i == total_beats - 1) ? 1'b1 : 1'b0;
            vif.wvalid <= 1'b1;

            fork
                begin
                    do begin
                        @(posedge vif.clk);
                    end while (!vif.wready);
                end
                begin
                    repeat (50000) @(posedge vif.clk);
                    `uvm_error("DRV_TIMEOUT", $sformatf("W channel ready timeout! beat=%0d", i))
                end
            join_any
            disable fork;
        end

        vif.wvalid <= 1'b0;
        vif.wlast  <= 1'b0;
    endtask: drive_w_channel

    virtual task b_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_tr;
        int match_idx;
        int unsigned stall_window = 0;

        forever begin
            @(posedge vif.clk);
            if (stall_window > 0) begin
                vif.bready <= 1'b0;
                stall_window--;
            end else begin
                vif.bready <= ($urandom_range(0, 99) < 75);
            end

            if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
                match_idx = -1;
                for (int i = 0; i < wr_in_flight_q.size(); i++) begin
                    if (wr_in_flight_q[i].id == vif.bid) begin
                        match_idx = i;
                        break;
                    end
                end

                if (match_idx != -1) begin
                    cur_tr = wr_in_flight_q[match_idx];
                    cur_tr.bresp = vif.bresp;
                    wr_in_flight_q.delete(match_idx);
                    cur_tr.set_id_info(cur_tr);
                    seq_item_port.put_response(cur_tr);
                end else begin
                    `uvm_error("DRV_BID_ERR", $sformatf("收到未知或未在途的 BID=0x%02x!", vif.bid))
                end

                // b_worker_process 与 r_worker_process 中：
                if ($urandom_range(0, 99) < 12) begin
                    stall_window = $urandom_range(24, 40);
                end
            end
        end
    endtask: b_worker_process

    virtual task ar_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;
        forever begin
            wait(rd_q.size() < MAX_QUEUE_DEPTH && rd_q.size() > 0 && rd_in_flight_q.size() < MAX_QUEUE_DEPTH);
            tr = rd_q.pop_front();

            tr.data.delete();
            rd_in_flight_q.push_back(tr);

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

            fork
                begin
                    do begin
                        @(posedge vif.clk);
                    end while (!vif.arready);
                end
                begin
                    repeat (50000) @(posedge vif.clk);
                    `uvm_error("DRV_TIMEOUT", $sformatf("AR channel ready timeout! addr=0x%08x", tr.addr))
                end
            join_any
            disable fork;

            vif.arvalid <= 1'b0;
        end
    endtask: ar_worker_process

    virtual task r_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_tr;
        int match_idx;
        int unsigned stall_window = 0;

        forever begin
            @(posedge vif.clk);
            if (stall_window > 0) begin
                vif.rready <= 1'b0;
                stall_window--;
            end else begin
                vif.rready <= ($urandom_range(0, 99) < 80);
            end

            if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
                match_idx = -1;
                for (int i = 0; i < rd_in_flight_q.size(); i++) begin
                    if (rd_in_flight_q[i].id == vif.rid) begin
                        match_idx = i;
                        break;
                    end
                end

                if (match_idx != -1) begin
                    cur_tr = rd_in_flight_q[match_idx];
                    cur_tr.data.push_back(vif.rdata);
                    cur_tr.rresp = vif.rresp;

                    if (vif.rlast === 1'b1) begin
                        rd_in_flight_q.delete(match_idx);
                        cur_tr.set_id_info(cur_tr);
                        seq_item_port.put_response(cur_tr);

                        // b_worker_process 与 r_worker_process 中：
                if ($urandom_range(0, 99) < 12) begin
                    stall_window = $urandom_range(24, 40);
                end
                    end
                end else begin
                    `uvm_error("DRV_RID_ERR", $sformatf("收到未知或未在途的 RID=0x%02x!", vif.rid))
                end
            end
        end
    endtask: r_worker_process

endclass: axi_driver

`endif // AXI_DRIVER_SV

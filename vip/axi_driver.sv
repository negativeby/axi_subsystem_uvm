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

    // 读在途未决队列 (已发 AR 地址，等待 R 数据的事务)
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_in_flight_q[$];

    localparam int MAX_QUEUE_DEPTH = 8;

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
        `uvm_info("AXI_DRV", "Driver 进入多 Outstanding 解耦全并发就绪状态", UVM_MEDIUM)

        fork
            fetch_items_process();
            write_worker_process();
            ar_worker_process();    // 读地址发射
            r_worker_process();     // 读数据接收
        join
    endtask: run_phase

    virtual task reset_signals();
        vif.awvalid <= 1'b0;
        `uvm_info("DRV_DBG", "[AW] Handshake DONE!", UVM_LOW);
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

    // 事务分流器
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

    // 写工作引擎 (AW, W, B)
    virtual task write_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;
        forever begin
            wait(wr_q.size() > 0);
            tr = wr_q.pop_front();
            drive_write(tr);

            tr.set_id_info(tr);
            seq_item_port.put_response(tr);
        end
    endtask: write_worker_process

    virtual task drive_write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        fork
            drive_aw_channel(tr);
            drive_w_channel(tr);
        join
        drive_b_channel(tr);
    endtask: drive_write

    virtual task drive_aw_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        `uvm_info("DRV_DBG", $sformatf("[%s] [AW] addr=0x%08x, len=%0d, size=%0d Start waiting for awready...", 
                  get_parent().get_name(), tr.addr, tr.len, tr.size), UVM_LOW)
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
                `uvm_error("DRV_TIMEOUT", $sformatf("AW channel ready timeout! addr=0x%08x, wr_q=%0d", tr.addr, wr_q.size()))
            end
        join_any
        disable fork;

        vif.awvalid <= 1'b0;
        `uvm_info("DRV_DBG", "[AW] Handshake DONE!", UVM_LOW);
    endtask: drive_aw_channel

    virtual task drive_w_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        int unsigned total_beats = tr.len + 1;
        `uvm_info("DRV_DBG", "[W] Start sending W beats...", UVM_LOW)
        @(posedge vif.clk);

        for (int i = 0; i < total_beats; i++) begin
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
        `uvm_info("DRV_DBG", "[W] All W beats DONE!", UVM_LOW);
    endtask: drive_w_channel

    virtual task drive_b_channel(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        vif.bready <= 1'b1;
        
        fork
            begin
                do begin
                    @(posedge vif.clk);
                end while (vif.bvalid !== 1'b1);
            end
            begin
                repeat (50000) @(posedge vif.clk);
                `uvm_error("DRV_TIMEOUT", "B channel response timeout (bvalid stuck low)")
            end
        join_any
        disable fork;

        tr.bresp   = vif.bresp;
        vif.bready <= 1'b0;
    endtask: drive_b_channel

    // 读地址发射引擎 (不等待数据，连发 AR)
    virtual task ar_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr;
        forever begin
            wait(rd_q.size() > 0);
            tr = rd_q.pop_front();

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
            rd_in_flight_q.push_back(tr);
        end
    endtask: ar_worker_process

    // 读数据接收引擎 (后台并行监听 R 通道，拼装数据)
    virtual task r_worker_process();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) cur_tr;
        int match_idx;

        forever begin
            @(posedge vif.clk);
            vif.rready <= 1'b1;

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
                    end
                end
            end
        end
    endtask: r_worker_process

endclass: axi_driver

`endif // AXI_DRIVER_SV

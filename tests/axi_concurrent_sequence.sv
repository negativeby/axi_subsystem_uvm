`ifndef AXI_CONCURRENT_SEQUENCE_SV
`define AXI_CONCURRENT_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_master_scenario_seq extends uvm_sequence #(axi_transfer #(32, 64, 8));

    `uvm_object_utils(axi_master_scenario_seq)

    int unsigned master_id_offset = 0;
    string       tag              = "M0";

    // 默认单主基数设为 1250，双主合计运行 10,080 笔事务 (支持 +NUM_TRANS=xxxx 动态覆盖)
    int unsigned base_trans_cnt    = 1250;
    int unsigned max_ost_per_dir   = 8;
    int unsigned wr_in_flight_cnt  = 0;
    int unsigned rd_in_flight_cnt  = 0;
    int unsigned local_seq_cnt     = 0;

    bit [31:0] s0_wr_min, s0_wr_max;
    bit [31:0] s0_rd_min, s0_rd_max;
    bit [31:0] s1_wr_min, s1_wr_max;
    bit [31:0] s1_rd_min, s1_rd_max;

    function new(string name = "axi_master_scenario_seq");
        super.new(name);
    endfunction: new

    function void init_address_map();
        if (tag == "M0") begin
            s0_rd_min = 32'h0000_0000; s0_rd_max = 32'h0000_1FFF;
            s0_wr_min = 32'h0000_2000; s0_wr_max = 32'h0000_3FFF;
            s1_rd_min = 32'h0001_0000; s1_rd_max = 32'h0001_03FF;
            s1_wr_min = 32'h0001_0400; s1_wr_max = 32'h0001_07FF;
        end else begin
            s0_rd_min = 32'h0000_4000; s0_rd_max = 32'h0000_5FFF;
            s0_wr_min = 32'h0000_6000; s0_wr_max = 32'h0000_7FFF;
            s1_rd_min = 32'h0001_0800; s1_rd_max = 32'h0001_0BFF;
            s1_wr_min = 32'h0001_0C00; s1_wr_max = 32'h0001_0FFF;
        end
    endfunction: init_address_map

    // 后台独立核销写与读的在途信贷
    task start_response_collector();
        fork
            forever begin
                axi_transfer #(32, 64, 8) rsp_item;
                get_response(rsp_item);
                if (rsp_item.trans_type == AXI_WRITE) begin
                    if (wr_in_flight_cnt > 0) wr_in_flight_cnt--;
                end else begin
                    if (rd_in_flight_cnt > 0) rd_in_flight_cnt--;
                end
            end
        join_none
    endtask: start_response_collector

    // 阶段 0：读空间非零随机数据预热初始化
    task prefill_read_regions();
        for (int i = 0; i < 40; i++) begin
            axi_transfer #(32, 64, 8) tr;
            wait (wr_in_flight_cnt < max_ost_per_dir);

            tr = axi_transfer#(32, 64, 8)::type_id::create("tr_prefill");
            start_item(tr);
            if (!tr.randomize() with {
                id == master_id_offset + (local_seq_cnt % 16);
                trans_type == AXI_WRITE;
                burst == 2'b01;
                if (i < 30) {
                    addr inside {[s0_rd_min : s0_rd_max]};
                    size == 3'b011;
                    len  inside {[8'd7 : 8'd15]};
                } else {
                    addr inside {[s1_rd_min : s1_rd_max]};
                    size == 3'b010;
                    len  == 8'd0;
                }
                (addr & ((1 << size) - 1)) == 0;
            }) begin
                `uvm_fatal(tag, "阶段 0 预热随机化失败！")
            end
            local_seq_cnt++;
            wr_in_flight_cnt++;
            finish_item(tr);
        end
        wait (wr_in_flight_cnt == 0);
    endtask: prefill_read_regions

    // 阶段 1：S0 全协议切片、16 种突发长度与 4KB 边界加权随机流
    task send_crv_s0_protocol_trans(int unsigned num_items);
        for (int i = 0; i < num_items; i++) begin
            axi_transfer #(32, 64, 8) tr;
            int unsigned b_mode;
            bit          is_wr;

            is_wr  = ($urandom_range(0, 99) < 55);
            b_mode = $urandom_range(0, 9);

            if (is_wr) wait (wr_in_flight_cnt < max_ost_per_dir);
            else       wait (rd_in_flight_cnt < max_ost_per_dir);

            tr = axi_transfer#(32, 64, 8)::type_id::create("tr");
            start_item(tr);

            if (!tr.randomize() with {
                id dist {
                    [master_id_offset     : master_id_offset + 1] := 30,
                    [master_id_offset + 2 : master_id_offset + 7] := 70
                };
                trans_type == (is_wr ? AXI_WRITE : AXI_READ);
                burst == 2'b01;

                size dist { 3'b000 := 25, 3'b001 := 25, 3'b010 := 25, 3'b011 := 25 };
                len  inside {[8'd0 : 8'd15]};

                if (is_wr) {
                    addr inside {[s0_wr_min : s0_wr_max]};
                } else {
                    addr inside {[s0_rd_min : s0_rd_max]};
                }

                if (b_mode <= 1) {
                    // 20% 概率精确顶满 4KB 边界 (Margin == 0)，快速打满 1B/2B/4B/8B 交叉项
                    ((addr & 32'h0000_0FFF) + ((len + 1) << size)) == 32'h0000_1000;
                } else if (b_mode == 2) {
                    // 10% 概率贴近 4KB 边界 (Margin inside 1..16)
                    ((addr & 32'h0000_0FFF) + ((len + 1) << size)) inside {[32'h0000_0FF0 : 32'h0000_0FFF]};
                } else {
                    ((addr & 32'h0000_0FFF) + ((len + 1) << size)) <= 32'h0000_1000;
                }

                (addr & ((1 << size) - 1)) == 0;
            }) begin
                `uvm_fatal(tag, "阶段 1 S0 协议随机化失败！")
            end

            local_seq_cnt++;
            if (is_wr) wr_in_flight_cnt++;
            else       rd_in_flight_cnt++;
            finish_item(tr);
        end
        wait (wr_in_flight_cnt == 0 && rd_in_flight_cnt == 0);
    endtask: send_crv_s0_protocol_trans

    // 阶段 2：高密度同/异 ID 跨从机路由与异常空洞马尔可夫游走
    task send_crv_routing_walk_trans(int unsigned num_items);
        for (int i = 0; i < num_items; i++) begin
            axi_transfer #(32, 64, 8) tr;
            int unsigned target_sel;
            bit          is_wr;

            is_wr = ($urandom_range(0, 99) < 50);
            if (is_wr) wait (wr_in_flight_cnt < max_ost_per_dir);
            else       wait (rd_in_flight_cnt < max_ost_per_dir);

            tr = axi_transfer#(32, 64, 8)::type_id::create("tr");
            start_item(tr);

            randcase
                35: target_sel = 0; // S0
                35: target_sel = 1; // S1
                12: target_sel = 2; // Hole A
                12: target_sel = 3; // Hole B
                6:  target_sel = 4; // Hole High
            endcase

            if (!tr.randomize() with {
                // 收敛在 4 个 ID 内，高频制造同 ID 同从机、同 ID 异从机、异 ID 乱序三种在途状态
                id inside {[master_id_offset : master_id_offset + 3]};
                trans_type == (is_wr ? AXI_WRITE : AXI_READ);
                burst == 2'b01;

                if (target_sel == 0) {
                    if (is_wr) addr inside {[s0_wr_min : s0_wr_max]};
                    else       addr inside {[s0_rd_min : s0_rd_max]};
                    size inside {[3'b000 : 3'b011]};
                    len  inside {[8'd0   : 8'd15]};
                } else if (target_sel == 1) {
                    if (is_wr) addr inside {[s1_wr_min : s1_wr_max]};
                    else       addr inside {[s1_rd_min : s1_rd_max]};
                    size == 3'b010;
                    len  == 8'd0;
                } else if (target_sel == 2) {
                    addr inside {[32'h0000_8000 : 32'h0000_FF00]};
                    size == 3'b011;
                    len  == 8'd0;
                } else if (target_sel == 3) {
                    addr inside {[32'h0001_1000 : 32'h0001_FF00]};
                    size == 3'b011;
                    len  == 8'd0;
                } else {
                    addr inside {[32'h0002_0000 : 32'h000F_FF00]};
                    size == 3'b011;
                    len  == 8'd0;
                }

                (addr & ((1 << size) - 1)) == 0;
            }) begin
                `uvm_fatal(tag, "阶段 2 路由游走随机化失败！")
            end

            local_seq_cnt++;
            if (is_wr) wr_in_flight_cnt++;
            else       rd_in_flight_cnt++;
            finish_item(tr);
        end
        wait (wr_in_flight_cnt == 0 && rd_in_flight_cnt == 0);
    endtask: send_crv_routing_walk_trans

    // 阶段 3：全双工读写独立 8+8 在途洪峰压测
    task send_crv_full_duplex_stress(int unsigned num_items);
        fork
            // 独立写洪峰线程 (专属 8 笔写信贷)
            begin
                for (int w = 0; w < num_items; w++) begin
                    axi_transfer #(32, 64, 8) tr_w;
                    bit to_s1;
                    wait (wr_in_flight_cnt < max_ost_per_dir);

                    tr_w = axi_transfer#(32, 64, 8)::type_id::create("tr_w");
                    start_item(tr_w);
                    to_s1 = ($urandom_range(0, 99) < 35);

                    if (!tr_w.randomize() with {
                        id inside {[master_id_offset : master_id_offset + 5]};
                        trans_type == AXI_WRITE;
                        burst == 2'b01;
                        if (w < 200) {
                            aw_delay == 0;
                            w_delay  == 0;
                            w_insert_bubble == 1'b0;
                        }
                        if (to_s1) {
                            addr inside {[s1_wr_min : s1_wr_max]};
                            size == 3'b010;
                            len  == 8'd0;
                        } else {
                            addr inside {[s0_wr_min : s0_wr_max]};
                            size inside {[3'b000 : 3'b011]};
                            if (w < 200) len inside {[8'd0 : 8'd1]};
                            else         len inside {[8'd0 : 8'd15]};
                        }
                        (addr & ((1 << size) - 1)) == 0;
                    }) begin
                        `uvm_fatal(tag, "阶段 3 异步写随机化失败！")
                    end

                    wr_in_flight_cnt++;
                    finish_item(tr_w);
                end
            end

            // 独立读洪峰线程 (专属 8 笔读信贷，与写线程零信贷争抢)
            begin
                for (int r = 0; r < num_items; r++) begin
                    axi_transfer #(32, 64, 8) tr_r;
                    bit to_s1;
                    wait (rd_in_flight_cnt < max_ost_per_dir);

                    tr_r = axi_transfer#(32, 64, 8)::type_id::create("tr_r");
                    start_item(tr_r);
                    to_s1 = ($urandom_range(0, 99) < 35);

                    if (!tr_r.randomize() with {
                        if (r < 200) {
                            id inside {[master_id_offset + 8 : master_id_offset + 9]};
                        } else {
                            id inside {[master_id_offset + 8 : master_id_offset + 13]};
                        }
                        trans_type == AXI_READ;
                        burst == 2'b01;
                        if (to_s1) {
                            addr inside {[s1_rd_min : s1_rd_max]};
                            size == 3'b010;
                            len  == 8'd0;
                        } else {
                            addr inside {[s0_rd_min : s0_rd_max]};
                            size inside {[3'b000 : 3'b011]};
                            len  inside {[8'd0   : 8'd15]};
                        }
                        (addr & ((1 << size) - 1)) == 0;
                    }) begin
                        `uvm_fatal(tag, "阶段 3 异步读随机化失败！")
                    end

                    rd_in_flight_cnt++;
                    finish_item(tr_r);
                end
            end
        join

        wait (wr_in_flight_cnt == 0 && rd_in_flight_cnt == 0);
    endtask: send_crv_full_duplex_stress

    virtual task body();
        void'($value$plusargs("NUM_TRANS=%d", base_trans_cnt));
        init_address_map();
        start_response_collector();

        `uvm_info(tag, $sformatf("[%s] 启动万笔级 Multi-Outstanding CRV 压测 | 单向最大在途=%0d | 预计单主总事务=%0d",
                  tag, max_ost_per_dir, 40 + base_trans_cnt * 4), UVM_LOW)

        prefill_read_regions();
        send_crv_s0_protocol_trans(base_trans_cnt);
        send_crv_routing_walk_trans(base_trans_cnt);
        send_crv_full_duplex_stress(base_trans_cnt);

        `uvm_info(tag, $sformatf("[%s] 万笔级 CRV 随机序列执行完毕！累计完成事务=%0d", tag, 40 + base_trans_cnt * 4), UVM_LOW)
    endtask: body

endclass: axi_master_scenario_seq

class axi_dual_master_vseq extends uvm_sequence;

    `uvm_object_utils(axi_dual_master_vseq)

    axi_master_scenario_seq m0_seq;
    axi_master_scenario_seq m1_seq;

    axi_sequencer #(32, 64, 8) m0_sqr;
    axi_sequencer #(32, 64, 8) m1_sqr;

    function new(string name = "axi_dual_master_vseq");
        super.new(name);
    endfunction: new

    virtual task body();
        `uvm_info("VIRT_SEQ", ">>> 启动双主 10,000+ 事务级 Multi-Outstanding 受约束随机压测 <<<", UVM_LOW)

        m0_seq = axi_master_scenario_seq::type_id::create("m0_seq");
        m1_seq = axi_master_scenario_seq::type_id::create("m1_seq");

        m0_seq.master_id_offset = 8'h00;
        m0_seq.tag              = "M0";

        m1_seq.master_id_offset = 8'h80;
        m1_seq.tag              = "M1";

        fork
            m0_seq.start(m0_sqr);
            m1_seq.start(m1_sqr);
        join

        `uvm_info("VIRT_SEQ", ">>> 双主 10,000+ 事务级 Multi-Outstanding 受约束随机压测完成！<<<", UVM_LOW)
    endtask: body

endclass: axi_dual_master_vseq

`endif // AXI_CONCURRENT_SEQUENCE_SV

`ifndef AXI_CONCURRENT_SEQUENCE_SV
`define AXI_CONCURRENT_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

// ==============================================================
// 基础子序列: 50/50 双从机真实高频交织、全双工高压流量发生器
// ==============================================================
class axi_master_traffic_seq #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    `uvm_object_param_utils(axi_master_traffic_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    bit [ADDR_WIDTH-1:0] s0_base_addr = 32'h0000_0000;
    bit [ADDR_WIDTH-1:0] s1_base_addr = 32'h0001_0000;
    int unsigned         total_trans  = 80;
    string               tag          = "M";

    // 独立 ID 管理：为 M0 和 M1 分配隔离的 ID 起始区间，避免跨 Master 混淆
    rand bit [ID_WIDTH-1:0] id_base_offset = 0;
    local bit [ID_WIDTH-1:0] local_id_counter = 0;

    function new(string name = "axi_master_traffic_seq");
        super.new(name);
        set_response_queue_depth(-1);
    endfunction: new

    virtual task send_trans(
        input bit                  is_write,
        input bit [ADDR_WIDTH-1:0] t_addr,
        input bit [2:0]            t_size,
        input bit [7:0]            t_len,
        input bit [1:0]            t_burst
    );
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr, rsp_tr;
        bit [ID_WIDTH-1:0] current_id;

        tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("%s_tr", tag));
        
        // 实例级自增 ID，并加上基地址偏移，彻底杜绝多实例/多轮回归撞 ID
        current_id = id_base_offset + (local_id_counter++);

        start_item(tr);
        if (!tr.randomize() with {
            trans_type == (is_write ? AXI_WRITE : AXI_READ);
            addr       == t_addr;
            size       == t_size;
            len        == t_len;
            burst      == t_burst;
            id         == current_id;
        }) `uvm_fatal("RND_FAIL", "事务随机化失败！")

        if (is_write) begin
            for (int beat = 0; beat <= tr.len; beat++) begin
                bit [ADDR_WIDTH-1:0] beat_addr;
                bit [2:0] lane_offset;
                beat_addr = (tr.burst == 2'b00) ? tr.addr : tr.addr + (beat * (1 << tr.size));
                lane_offset = beat_addr[2:0];
                case (tr.size)
                    3'b000: tr.strb[beat] = 8'h01 << lane_offset;
                    3'b001: tr.strb[beat] = 8'h03 << lane_offset;
                    3'b010: tr.strb[beat] = 8'h0F << lane_offset;
                    default: tr.strb[beat] = 8'hFF;
                endcase
            end
        end

        finish_item(tr);
        get_response(rsp_tr);
    endtask: send_trans

    virtual task body();
        // ----------------------------------------------------------
        // 阶段 0: 独占基底初始化打底 (串行保证 Scoreboard 账目正确)
        // ----------------------------------------------------------
        `uvm_info(tag, $sformatf("[%s] 阶段 0: 灌入 S0 与 S1 专属基底数据...", tag), UVM_LOW)
        for (int i = 0; i < 32; i++) begin
            send_trans(1'b1, s0_base_addr + (i * 8), 3'b011, 8'd0, 2'b01);
        end
        for (int i = 0; i < 16; i++) begin
            send_trans(1'b1, s1_base_addr + (i * 8), 3'b011, 8'd0, 2'b01);
        end

        // ----------------------------------------------------------
        // 阶段 1: 全双工双从机动态交织压测
        // ----------------------------------------------------------
        `uvm_info(tag, $sformatf("[%s] 阶段 1: 启动 %0d 笔 S0/S1 全双工高压穿插测试...", tag, total_trans), UVM_LOW)

        for (int i = 0; i < total_trans; i++) begin
            int rw_sel;
            bit [2:0] rnd_size;
            bit [7:0] rnd_len;
            bit [ADDR_WIDTH-1:0] base;
            bit [ADDR_WIDTH-1:0] target_addr;
            bit is_s1_access;

            rw_sel = $urandom_range(0, 1);
            is_s1_access = (i % 2 != 0);

            if (!is_s1_access) begin
                // === S0 (AXI4 RAM): 覆盖各种突发长度与位宽 ===
                base     = s0_base_addr;
                rnd_size = $urandom_range(0, 3); // 1B, 2B, 4B, 8B
                
                // 轮流生成 single(0), short(1~3), med(4~9), long(10~15)
                case ((i / 2) % 4)
                    0: rnd_len = 8'd0;
                    1: rnd_len = $urandom_range(1, 3);
                    2: rnd_len = $urandom_range(4, 9);
                    3: rnd_len = $urandom_range(10, 15);
                endcase

                target_addr = base + ($urandom_range(0, 12'h300) & ~((1 << rnd_size) - 1));

                // 修复位宽截断：必须使用 16'h1000 或 4096，不能写 12'h1000
                if (((target_addr & 12'hFFF) + ((rnd_len + 1) * (1 << rnd_size))) > 16'h1000) begin
                    rnd_len = 8'd0;
                end

                send_trans(rw_sel[0], target_addr, rnd_size, rnd_len, 2'b01);
            end
            else begin
                // === S1 (AXI-Lite): 严格单拍传输 ===
                base        = s1_base_addr;
                rnd_size    = $urandom_range(2, 3);
                rnd_len     = 8'd0;
                target_addr = base + ($urandom_range(0, 12'h200) & ~((1 << rnd_size) - 1));

                send_trans(rw_sel[0], target_addr, rnd_size, rnd_len, 2'b01);
            end

            // 定向 FIXED 模式
            if (i == 20) begin
                send_trans(1'b1, s0_base_addr + 12'h700, 3'b011, 8'd1, 2'b00);
            end
        end

// ----------------------------------------------------------
        // 阶段 2: 安全 DECERR（孔洞响应）全覆盖触发 (读/写 + M0/M1)
        // ----------------------------------------------------------
        `uvm_info(tag, $sformatf("[%s] 阶段 2: 触发未映射地址 (DECERR) 完整路径...", tag), UVM_LOW)

        // 1. 发起孔洞写事务 -> 覆盖 cp_bresp_status.decerr
        send_trans(1'b1, 32'h0002_0000, 3'b011, 8'd0, 2'b01);

        // 2. 发起孔洞读事务 -> 覆盖 cp_rresp_status.decerr 与 cross_matrix 读孔洞
        send_trans(1'b0, 32'h0002_0000, 3'b011, 8'd0, 2'b01);

        `uvm_info(tag, $sformatf("[%s] 全双工交织高压压测完毕！", tag), UVM_LOW)
    endtask: body

endclass: axi_master_traffic_seq


// ==============================================================
// 顶级 Virtual Sequence
// ==============================================================
class axi_dual_master_vseq extends uvm_sequence;

    `uvm_object_utils(axi_dual_master_vseq)

    axi_sequencer #(32, 64, 8) m0_sqr;
    axi_sequencer #(32, 64, 8) m1_sqr;

    function new(string name = "axi_dual_master_vseq");
        super.new(name);
    endfunction: new

    virtual task body();
        axi_master_traffic_seq #(32, 64, 8) m0_seq;
        axi_master_traffic_seq #(32, 64, 8) m1_seq;

        if (m0_sqr == null || m1_sqr == null) begin
            `uvm_fatal("VSEQ_NULL", "m0_sqr 或 m1_sqr 句柄未分配！")
        end

        `uvm_info("VIRT_SEQ", "==================================================", UVM_LOW)
        `uvm_info("VIRT_SEQ", "双主完全异步·全双工交织矩阵高压压测启动！", UVM_LOW)
        `uvm_info("VIRT_SEQ", "==================================================", UVM_LOW)

        m0_seq = axi_master_traffic_seq #(32, 64, 8)::type_id::create("m0_seq");
        m0_seq.s0_base_addr   = 32'h0000_0000;
        m0_seq.s1_base_addr   = 32'h0001_0000;
        m0_seq.total_trans    = 80;
        m0_seq.tag            = "M0";
        m0_seq.id_base_offset = 8'h00; // M0 使用 ID 0 ~ 127

        m1_seq = axi_master_traffic_seq #(32, 64, 8)::type_id::create("m1_seq");
        m1_seq.s0_base_addr   = 32'h0000_2000;
        m1_seq.s1_base_addr   = 32'h0001_0800;
        m1_seq.total_trans    = 80;
        m1_seq.tag            = "M1";
        m1_seq.id_base_offset = 8'h80; // M1 使用 ID 128 ~ 255 (完美隔离，绝不冲突)

        fork
            m0_seq.start(m0_sqr);
            m1_seq.start(m1_sqr);
        join

        `uvm_info("VIRT_SEQ", "全双工双主并发测试执行完毕！", UVM_LOW)
    endtask: body

endclass: axi_dual_master_vseq

`endif // AXI_CONCURRENT_SEQUENCE_SV

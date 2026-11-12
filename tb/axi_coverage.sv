`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

typedef enum bit {
    MASTER_M0 = 1'b0,
    MASTER_M1 = 1'b1
} master_id_e;

typedef enum bit [2:0] {
    SLV_S0      = 3'd0,
    SLV_S1      = 3'd1,
    SLV_HOLE_A  = 3'd2,
    SLV_HOLE_B  = 3'd3,
    SLV_HOLE_HI = 3'd4
} slave_target_e;

// 细化为 4 种真实物理写交织形态
typedef enum bit [1:0] {
    AW_BEFORE_W_FIRST        = 2'b00, // AW 先于 W 首拍完成握手
    AW_W_FIRST_ALIGNED       = 2'b01, // AW 与 W 首拍在同一时钟沿同时握手
    W_FIRST_BEFORE_AW_PART   = 2'b10, // W 首拍先握手，AW 在突发中途或末拍到达
    W_FULL_BURST_BEFORE_AW   = 2'b11  // 整包 W (含 WLAST) 全部握手完毕后，AW 才完成握手
} aw_w_timing_e;

// Crossbar 核心微架构：在途 ID 冲突与保序状态枚举
typedef enum bit [1:0] {
    HAZ_EMPTY_PIPELINE   = 2'b00, // 当前无在途事务，空流水线直接派发
    HAZ_DIFF_ID_OOO      = 2'b01, // 存在在途事务但 ID 均不同，允许跨从机乱序并发
    HAZ_SAME_ID_SAME_SLV = 2'b10, // 存在同 ID 在途事务且目标从机相同，同路保序流水
    HAZ_SAME_ID_DIFF_SLV = 2'b11  // 存在同 ID 在途事务且目标从机不同，触发硬件保序阻塞！
} id_hazard_e;

// W 通道单拍物理交互状态
typedef enum bit [1:0] {
    W_BEAT_TRANSFER = 2'b00, // 正常数据传输 (wvalid && wready)
    W_MASTER_BUBBLE = 2'b01, // 主机突发中途断流气泡 (!wvalid && wready)
    W_SLAVE_STALL   = 2'b10  // 从机或矩阵反压等待 (wvalid && !wready)
} w_pipe_state_e;

class axi_coverage extends uvm_subscriber #(axi_transfer #(32, 64, 8));

    `uvm_component_utils(axi_coverage)

    // 事务级采样载体
    axi_transfer #(32, 64, 8) m_tr;
    master_id_e               cur_master;
    slave_target_e            cur_target;
    slave_target_e            prev_target[2];
    bit                       has_prev[2];

    // 双主虚接口句柄
    virtual axi_if #(32, 64, 8) vif_m0;
    virtual axi_if #(32, 64, 8) vif_m1;

    // 维度 4 采样载体
    master_id_e   timing_master;
    aw_w_timing_e cur_timing_mode;
    bit           timing_is_multi_beat;

    // 维度 5 (微架构流水线与反压) 采样载体
    master_id_e    pipe_master;
    trans_type_e   pipe_dir;
    int unsigned   cur_ost_depth;
    id_hazard_e    cur_hazard_mode;
    int unsigned   cur_addr_stall_cycles;
    w_pipe_state_e cur_w_pipe_state;
    bit            cur_b_backpressure;
    bit            cur_r_backpressure;

    // ==============================================================
    // 维度 1: 事务层全离散突发长度、窄传输掩码与 4KB 边界三维交叉
    // ==============================================================
    covergroup cg_axi_trans;
        option.per_instance = 1;
        option.name         = "cg_axi_trans_detail";
        option.at_least     = 5;

        cp_dir: coverpoint m_tr.trans_type {
            bins write = {AXI_WRITE};
            bins read  = {AXI_READ};
        }

        cp_len: coverpoint m_tr.len {
            bins len_val[] = {[8'd0 : 8'd15]};
        }

        cp_size: coverpoint m_tr.size {
            bins sz_1b = {3'b000};
            bins sz_2b = {3'b001};
            bins sz_4b = {3'b010};
            bins sz_8b = {3'b011};
            illegal_bins inv = default;
        }

        cp_addr_offset: coverpoint (m_tr.addr[2:0]) {
            bins offset_lane[] = {[3'd0 : 3'd7]};
        }

        cp_wstrb_first_beat: coverpoint (m_tr.strb.size() > 0 ? m_tr.strb[0] : 8'h00)
            iff (m_tr.trans_type == AXI_WRITE) {
            bins b1_lanes[] = {8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
            bins b2_lanes[] = {8'h03, 8'h0C, 8'h30, 8'hC0};
            bins b4_lanes[] = {8'h0F, 8'hF0};
            bins b8_full    = {8'hFF};
        }

        cp_4kb_margin: coverpoint (13'h1000 - ((m_tr.addr[11:0]) + ((m_tr.len + 1) << m_tr.size)))
            iff (m_tr.burst == 2'b01 && m_tr.addr <= 32'h0000_7FFF &&
                ((m_tr.addr[11:0] + ((m_tr.len + 1) << m_tr.size)) <= 13'h1000)) {
            bins hit_exact_boundary = {13'd0};            // 恰好顶满 4KB 边界 (Margin == 0)
            bins near_boundary      = {[13'd1 : 13'd16]}; // 贴近边界 (剩余 1~16 字节)
            bins normal_region      = {[13'd17: 13'h1000]};
        }

        // 三维交叉 1: 读写方向 x 传输位宽 x 字节通道偏移 (确保读和写均覆盖全部窄通道)
        cross_dir_x_size_x_offset: cross cp_dir, cp_size, cp_addr_offset {
            ignore_bins unaligned_b8 = binsof(cp_size.sz_8b) && !binsof(cp_addr_offset) intersect {3'd0};
            ignore_bins unaligned_b4 = binsof(cp_size.sz_4b) && !binsof(cp_addr_offset) intersect {3'd0, 3'd4};
            ignore_bins unaligned_b2 = binsof(cp_size.sz_2b) && !binsof(cp_addr_offset) intersect {3'd0, 3'd2, 3'd4, 3'd6};
        }

        // 三维交叉 2: 读写方向 x 传输位宽 x 16种突发长度 (2 x 4 x 16 = 128 bins)
        cross_dir_x_size_x_len: cross cp_dir, cp_size, cp_len;

        // 交叉 3: 4KB 边界贴边深度 x 传输位宽 (检验 1B/2B/4B/8B 是否各自触发过精确 4KB 贴边)
        cross_4kb_x_size: cross cp_4kb_margin, cp_size;

    endgroup: cg_axi_trans

    // ==============================================================
    // 维度 2: 独立主设备拓扑路由、四维跨从机状态切换与异常恢复
    // ==============================================================
    covergroup cg_axi_routing;
        option.per_instance = 1;
        option.name         = "cg_axi_routing";
        option.at_least     = 5;

        cp_master: coverpoint cur_master {
            bins m0 = {MASTER_M0};
            bins m1 = {MASTER_M1};
        }

        cp_dir: coverpoint m_tr.trans_type {
            bins write = {AXI_WRITE};
            bins read  = {AXI_READ};
        }

        cp_target_slave: coverpoint cur_target {
            bins s0_axi_ram  = {SLV_S0};
            bins s1_axil_ram = {SLV_S1};
            bins hole_a      = {SLV_HOLE_A};
            bins hole_b      = {SLV_HOLE_B};
            bins hole_high   = {SLV_HOLE_HI};
        }

        cp_prev_slave: coverpoint prev_target[cur_master] iff (has_prev[cur_master]) {
            bins from_s0   = {SLV_S0};
            bins from_s1   = {SLV_S1};
            bins from_hole = {SLV_HOLE_A, SLV_HOLE_B, SLV_HOLE_HI};
        }

        cp_cur_slave_group: coverpoint cur_target iff (has_prev[cur_master]) {
            bins to_s0   = {SLV_S0};
            bins to_s1   = {SLV_S1};
            bins to_hole = {SLV_HOLE_A, SLV_HOLE_B, SLV_HOLE_HI};
        }

        cp_resp_status: coverpoint (m_tr.trans_type == AXI_WRITE ? m_tr.bresp : m_tr.rresp) {
            bins okay   = {2'b00};
            bins decerr = {2'b11};
            ignore_bins other = {2'b01, 2'b10};
        }

        cross_matrix_full: cross cp_master, cp_target_slave, cp_dir;

        // 四维交叉: 主设备 x 前态从机 x 当前从机 x 读写方向 (2 x 3 x 3 x 2 = 36 bins)
        cross_single_master_transition_dir: cross cp_master, cp_prev_slave, cp_cur_slave_group, cp_dir;

        cross_slave_resp_check: cross cp_target_slave, cp_resp_status {
            illegal_bins err_on_s0    = binsof(cp_target_slave.s0_axi_ram)  && binsof(cp_resp_status.decerr);
            illegal_bins err_on_s1    = binsof(cp_target_slave.s1_axil_ram) && binsof(cp_resp_status.decerr);
            illegal_bins okay_on_hole = (binsof(cp_target_slave.hole_a) ||
                                         binsof(cp_target_slave.hole_b) ||
                                         binsof(cp_target_slave.hole_high)) && binsof(cp_resp_status.okay);
        }

    endgroup: cg_axi_routing

    // ==============================================================
    // 维度 3: 2x2 矩阵并发仲裁与全双工读写同步碰撞模型
    // ==============================================================
    function automatic bit [1:0] decode_slave_target(bit valid, bit [31:0] addr);
        if (!valid) return 2'b00; // IDLE
        if (addr <= 32'h0000_7FFF) return 2'b01; // S0
        if (addr >= 32'h0001_0000 && addr <= 32'h0001_0FFF) return 2'b10; // S1
        return 2'b11; // HOLE / DECERR
    endfunction

    covergroup cg_axi_arbitration;
        option.per_instance = 1;
        option.name         = "cg_axi_arbitration_stress";
        option.at_least     = 5;

        cp_aw_m0_target: coverpoint decode_slave_target(vif_m0.awvalid, vif_m0.awaddr) {
            bins idle    = {2'b00};
            bins to_s0   = {2'b01};
            bins to_s1   = {2'b10};
            bins to_hole = {2'b11};
        }

        cp_aw_m1_target: coverpoint decode_slave_target(vif_m1.awvalid, vif_m1.awaddr) {
            bins idle    = {2'b00};
            bins to_s0   = {2'b01};
            bins to_s1   = {2'b10};
            bins to_hole = {2'b11};
        }

        cp_ar_m0_target: coverpoint decode_slave_target(vif_m0.arvalid, vif_m0.araddr) {
            bins idle    = {2'b00};
            bins to_s0   = {2'b01};
            bins to_s1   = {2'b10};
            bins to_hole = {2'b11};
        }

        cp_ar_m1_target: coverpoint decode_slave_target(vif_m1.arvalid, vif_m1.araddr) {
            bins idle    = {2'b00};
            bins to_s0   = {2'b01};
            bins to_s1   = {2'b10};
            bins to_hole = {2'b11};
        }

        cross_aw_arbitration: cross cp_aw_m0_target, cp_aw_m1_target {
            bins collision_s0          = binsof(cp_aw_m0_target.to_s0) && binsof(cp_aw_m1_target.to_s0);
            bins collision_s1          = binsof(cp_aw_m0_target.to_s1) && binsof(cp_aw_m1_target.to_s1);
            bins parallel_orthogonal_0 = binsof(cp_aw_m0_target.to_s0) && binsof(cp_aw_m1_target.to_s1);
            bins parallel_orthogonal_1 = binsof(cp_aw_m0_target.to_s1) && binsof(cp_aw_m1_target.to_s0);
            ignore_bins both_idle      = binsof(cp_aw_m0_target.idle)  && binsof(cp_aw_m1_target.idle);
            ignore_bins with_hole      = binsof(cp_aw_m0_target.to_hole) || binsof(cp_aw_m1_target.to_hole);
            ignore_bins one_idle       = binsof(cp_aw_m0_target.idle)  || binsof(cp_aw_m1_target.idle);
        }

        cross_ar_arbitration: cross cp_ar_m0_target, cp_ar_m1_target {
            bins collision_s0          = binsof(cp_ar_m0_target.to_s0) && binsof(cp_ar_m1_target.to_s0);
            bins collision_s1          = binsof(cp_ar_m0_target.to_s1) && binsof(cp_ar_m1_target.to_s1);
            bins parallel_orthogonal_0 = binsof(cp_ar_m0_target.to_s0) && binsof(cp_ar_m1_target.to_s1);
            bins parallel_orthogonal_1 = binsof(cp_ar_m0_target.to_s1) && binsof(cp_ar_m1_target.to_s0);
            ignore_bins both_idle      = binsof(cp_ar_m0_target.idle)  && binsof(cp_ar_m1_target.idle);
            ignore_bins with_hole      = binsof(cp_ar_m0_target.to_hole) || binsof(cp_ar_m1_target.to_hole);
            ignore_bins one_idle       = binsof(cp_ar_m0_target.idle)  || binsof(cp_ar_m1_target.idle);
        }

        // 新增全双工并发交叉：当写通道发生双主争抢或正交时，读通道同时也在发生双主争抢或正交
        cross_full_duplex_rw_active: cross cross_aw_arbitration, cross_ar_arbitration;
    endgroup: cg_axi_arbitration

    // ==============================================================
    // 维度 4: 写通道 AW 与 W 首拍/末拍精确相对时序交织模型
    // ==============================================================
    covergroup cg_axi_handshake_timing;
        option.per_instance = 1;
        option.name         = "cg_axi_handshake_timing";
        option.at_least     = 5;

        cp_timing_master: coverpoint timing_master {
            bins m0 = {MASTER_M0};
            bins m1 = {MASTER_M1};
        }

        cp_aw_w_order: coverpoint cur_timing_mode {
            bins aw_first_before_w    = {AW_BEFORE_W_FIRST};
            bins aw_w_first_aligned   = {AW_W_FIRST_ALIGNED};
            bins w_first_part_lead    = {W_FIRST_BEFORE_AW_PART};
            bins w_full_burst_lead    = {W_FULL_BURST_BEFORE_AW};
        }

        cp_burst_type: coverpoint timing_is_multi_beat {
            bins single_beat = {1'b0};
            bins multi_beat  = {1'b1};
        }

        // 交叉: 主设备 x 4种时序形态 x 单拍/多拍突发
        // (注：单拍突发下 w_first_part_lead 物理上不存在，因為首拍即末拍，自动归入 w_full_burst_lead)
        cross_master_x_timing_x_burst: cross cp_timing_master, cp_aw_w_order, cp_burst_type {
            ignore_bins single_part_impossible = binsof(cp_aw_w_order.w_first_part_lead) &&
                                                 binsof(cp_burst_type.single_beat);
        }
    endgroup: cg_axi_handshake_timing

    // ==============================================================
    // 维度 5: 微架构在途深度、同/异 ID 冲突与五通道反压模型
    // ==============================================================
    covergroup cg_axi_pipeline_addr;
        option.per_instance = 1;
        option.name         = "cg_axi_pipeline_addr";
        option.at_least     = 5;

        cp_master: coverpoint pipe_master {
            bins m0 = {MASTER_M0};
            bins m1 = {MASTER_M1};
        }

        cp_dir: coverpoint pipe_dir {
            bins write = {AXI_WRITE};
            bins read  = {AXI_READ};
        }

        
        // 1. 新请求握手后的实时在途事务总深度 (1:单笔无积压, 2:双在途, 3:中度在途, 4+:满负荷深度在途)
        cp_ost_depth: coverpoint cur_ost_depth {
            bins depth_1_single  = {1};
            bins depth_2_double  = {2};
            bins depth_3_medium  = {3};
            bins depth_4_plus_hi = {[4 : 16]};
        }

        // 2. 新请求进入时的在途 ID 保序冲突类型
        cp_id_hazard: coverpoint cur_hazard_mode {
            bins empty_pipe       = {HAZ_EMPTY_PIPELINE};
            bins diff_id_ooo      = {HAZ_DIFF_ID_OOO};
            bins same_id_same_slv = {HAZ_SAME_ID_SAME_SLV};
            bins same_id_diff_slv = {HAZ_SAME_ID_DIFF_SLV};
        }

        // 3. 地址通道从 valid 置起到 ready 握手的真实硬件反压等待拍数 (剔除物理不可达的 0 拍)
        cp_addr_stall: coverpoint cur_addr_stall_cycles {
            bins stall_1_2_min_lat  = {[1 : 2]};    // Crossbar 状态机最小固有译码延迟
            bins stall_3_5_arb      = {[3 : 5]};    // 仲裁竞争或轻度排队
            bins stall_6_10_cong    = {[6 : 10]};   // M_ISSUE 满限流或从机反压等待
            bins stall_11_plus_deep = {[11 : 5000]};// 同 ID 跨从机保序阻塞或重度拥塞
        }

        // 交叉: 主设备 x 读写方向 x 在途深度
        cross_master_dir_ost: cross cp_master, cp_dir, cp_ost_depth;

        // 交叉: 主设备 x 读写方向 x ID 冲突类型
        cross_master_dir_hazard: cross cp_master, cp_dir, cp_id_hazard;

        // 交叉: ID 冲突类型 x 地址反压等待拍数
        cross_hazard_x_stall: cross cp_id_hazard, cp_addr_stall;
    endgroup: cg_axi_pipeline_addr

    covergroup cg_axi_backpressure_data;
        option.per_instance = 1;
        option.name         = "cg_axi_backpressure_data";
        option.at_least     = 10;

        cp_w_state: coverpoint cur_w_pipe_state {
            bins normal_beat   = {W_BEAT_TRANSFER};
            bins master_bubble = {W_MASTER_BUBBLE}; // !wvalid && wready (主机中途断流气泡)
            bins slave_stall   = {W_SLAVE_STALL};   // wvalid && !wready (从机或矩阵反压)
        }

        cp_b_stall: coverpoint cur_b_backpressure {
            bins b_ready_ok    = {1'b0};
            bins b_backpress   = {1'b1}; // bvalid && !bready
        }

        cp_r_stall: coverpoint cur_r_backpressure {
            bins r_ready_ok    = {1'b0};
            bins r_backpress   = {1'b1}; // rvalid && !rready
        }
    endgroup: cg_axi_backpressure_data

    // ==============================================================
    // UVM 标准方法与多线程监测引擎
    // ==============================================================
    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_axi_trans             = new();
        cg_axi_routing           = new();
        cg_axi_arbitration       = new();
        cg_axi_handshake_timing  = new();
        cg_axi_pipeline_addr     = new();
        cg_axi_backpressure_data = new();
        has_prev[0]              = 1'b0;
        has_prev[1]              = 1'b0;
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if#(32, 64, 8))::get(this, "", "vif_m0", vif_m0))
            `uvm_fatal("COV_NOVIF", "axi_coverage 无法获取 vif_m0！")
        if (!uvm_config_db#(virtual axi_if#(32, 64, 8))::get(this, "", "vif_m1", vif_m1))
            `uvm_fatal("COV_NOVIF", "axi_coverage 无法获取 vif_m1！")
    endfunction: build_phase

    function automatic slave_target_e map_addr_to_slave(bit [31:0] addr);
        if (addr <= 32'h0000_7FFF) return SLV_S0;
        if (addr >= 32'h0001_0000 && addr <= 32'h0001_0FFF) return SLV_S1;
        if (addr >= 32'h0000_8000 && addr <= 32'h0000_FFFF) return SLV_HOLE_A;
        if (addr >= 32'h0001_1000 && addr <= 32'h0001_FFFF) return SLV_HOLE_B;
        return SLV_HOLE_HI;
    endfunction

    virtual function void write(axi_transfer #(32, 64, 8) t);
        m_tr       = t;
        cur_master = (t.id < 8'h80) ? MASTER_M0 : MASTER_M1;
        cur_target = map_addr_to_slave(t.addr);

        cg_axi_trans.sample();
        cg_axi_routing.sample();

        prev_target[cur_master] = cur_target;
        has_prev[cur_master]    = 1'b1;
    endfunction: write

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        fork
            monitor_handshake_timing(vif_m0, MASTER_M0);
            monitor_handshake_timing(vif_m1, MASTER_M1);
            monitor_pipeline_microarch(vif_m0, MASTER_M0);
            monitor_pipeline_microarch(vif_m1, MASTER_M1);
            monitor_arbitration_cycle();
        join
    endtask: run_phase

    task automatic monitor_arbitration_cycle();
        forever @(posedge vif_m0.clk) begin
            if (vif_m0.rst_n && vif_m1.rst_n) begin
                bit any_aw_hs = (vif_m0.awvalid && vif_m0.awready) || (vif_m1.awvalid && vif_m1.awready);
                bit any_ar_hs = (vif_m0.arvalid && vif_m0.arready) || (vif_m1.arvalid && vif_m1.arready);
                if (any_aw_hs || any_ar_hs) begin
                    cg_axi_arbitration.sample();
                end
            end
        end
    endtask: monitor_arbitration_cycle

    // 基于精确周期时间戳队列的 AW / W 交织采样引擎
    task automatic monitor_handshake_timing(virtual axi_if#(32, 64, 8) vif, master_id_e m_id);
        longint unsigned cycle_cnt = 0;
        longint unsigned aw_time_q[$];
        longint unsigned w_first_time_q[$];
        longint unsigned w_last_time_q[$];
        bit              w_multi_beat_q[$];

        longint unsigned cur_w_first_t = 0;
        int unsigned     cur_w_beats   = 0;
        bit              w_in_burst    = 0;

        forever @(posedge vif.clk) begin
            if (!vif.rst_n) begin
                cycle_cnt = 0;
                aw_time_q.delete();
                w_first_time_q.delete();
                w_last_time_q.delete();
                w_multi_beat_q.delete();
                w_in_burst  = 0;
                cur_w_beats = 0;
            end else begin
                cycle_cnt++;

                if (vif.awvalid && vif.awready) begin
                    aw_time_q.push_back(cycle_cnt);
                end

                if (vif.wvalid && vif.wready) begin
                    if (!w_in_burst) begin
                        cur_w_first_t = cycle_cnt;
                        cur_w_beats   = 1;
                        w_in_burst    = 1'b1;
                    end else begin
                        cur_w_beats++;
                    end

                    if (vif.wlast) begin
                        w_first_time_q.push_back(cur_w_first_t);
                        w_last_time_q.push_back(cycle_cnt);
                        w_multi_beat_q.push_back(cur_w_beats > 1);
                        w_in_burst  = 1'b0;
                        cur_w_beats = 0;
                    end
                end

                // 配对比较时间戳，精确区分 4 种物理时序形态
                while (aw_time_q.size() > 0 && w_first_time_q.size() > 0) begin
                    longint unsigned t_aw = aw_time_q.pop_front();
                    longint unsigned t_wf = w_first_time_q.pop_front();
                    longint unsigned t_wl = w_last_time_q.pop_front();
                    bit              is_m = w_multi_beat_q.pop_front();

                    timing_master        = m_id;
                    timing_is_multi_beat = is_m;

                    if (t_aw < t_wf) begin
                        cur_timing_mode = AW_BEFORE_W_FIRST;
                    end else if (t_aw == t_wf) begin
                        cur_timing_mode = AW_W_FIRST_ALIGNED;
                    end else if (t_aw > t_wl) begin
                        cur_timing_mode = W_FULL_BURST_BEFORE_AW;
                    end else begin
                        cur_timing_mode = W_FIRST_BEFORE_AW_PART;
                    end

                    cg_axi_handshake_timing.sample();
                end
            end
        end
    endtask: monitor_handshake_timing

    // 实时追踪微架构在途深度、同/异 ID 跨从机冲突、地址反压周期及数据气泡
    task automatic monitor_pipeline_microarch(virtual axi_if#(32, 64, 8) vif, master_id_e m_id);
        bit [7:0]        wr_id_q[$];
        slave_target_e   wr_slv_q[$];
        bit [7:0]        rd_id_q[$];
        slave_target_e   rd_slv_q[$];

        int unsigned     aw_stall_cnt = 0;
        int unsigned     ar_stall_cnt = 0;
        bit              w_burst_busy = 0;

        forever @(posedge vif.clk) begin
            if (!vif.rst_n) begin
                wr_id_q.delete();
                wr_slv_q.delete();
                rd_id_q.delete();
                rd_slv_q.delete();
                aw_stall_cnt = 0;
                ar_stall_cnt = 0;
                w_burst_busy = 0;
            end else begin
                // 1. 监测 AW 通道在途深度、ID 冲突与反压等待拍数
                if (vif.awvalid && !vif.awready) begin
                    aw_stall_cnt++;
                end else if (vif.awvalid && vif.awready) begin
                    slave_target_e slv = map_addr_to_slave(vif.awaddr);
                    id_hazard_e    haz = HAZ_EMPTY_PIPELINE;

                    if (wr_id_q.size() == 0) begin
                        haz = HAZ_EMPTY_PIPELINE;
                    end else begin
                        haz = HAZ_DIFF_ID_OOO;
                        for (int i = 0; i < wr_id_q.size(); i++) begin
                            if (wr_id_q[i] == vif.awid) begin
                                if (wr_slv_q[i] == slv)
                                    haz = HAZ_SAME_ID_SAME_SLV;
                                else
                                    haz = HAZ_SAME_ID_DIFF_SLV;
                                break;
                            end
                        end
                    end

                    pipe_master           = m_id;
                    pipe_dir              = AXI_WRITE;
                    cur_ost_depth         = wr_id_q.size()+ 1;
                    cur_hazard_mode       = haz;
                    cur_addr_stall_cycles = aw_stall_cnt;
                    cg_axi_pipeline_addr.sample();

                    wr_id_q.push_back(vif.awid);
                    wr_slv_q.push_back(slv);
                    aw_stall_cnt = 0;
                end

                // 核销已完成 B 握手的写事务
                if (vif.bvalid && vif.bready) begin
                    for (int i = 0; i < wr_id_q.size(); i++) begin
                        if (wr_id_q[i] == vif.bid) begin
                            wr_id_q.delete(i);
                            wr_slv_q.delete(i);
                            break;
                        end
                    end
                end

                // 2. 监测 AR 通道在途深度、ID 冲突与反压等待拍数
                if (vif.arvalid && !vif.arready) begin
                    ar_stall_cnt++;
                end else if (vif.arvalid && vif.arready) begin
                    slave_target_e slv = map_addr_to_slave(vif.araddr);
                    id_hazard_e    haz = HAZ_EMPTY_PIPELINE;

                    if (rd_id_q.size() == 0) begin
                        haz = HAZ_EMPTY_PIPELINE;
                    end else begin
                        haz = HAZ_DIFF_ID_OOO;
                        for (int i = 0; i < rd_id_q.size(); i++) begin
                            if (rd_id_q[i] == vif.arid) begin
                                if (rd_slv_q[i] == slv)
                                    haz = HAZ_SAME_ID_SAME_SLV;
                                else
                                    haz = HAZ_SAME_ID_DIFF_SLV;
                                break;
                            end
                        end
                    end

                    pipe_master           = m_id;
                    pipe_dir              = AXI_READ;
                    cur_ost_depth         = rd_id_q.size()+ 1;
                    cur_hazard_mode       = haz;
                    cur_addr_stall_cycles = ar_stall_cnt;
                    cg_axi_pipeline_addr.sample();

                    rd_id_q.push_back(vif.arid);
                    rd_slv_q.push_back(slv);
                    ar_stall_cnt = 0;
                end

                // 核销已完成 RLAST 握手的读事务
                if (vif.rvalid && vif.rready && vif.rlast) begin
                    for (int i = 0; i < rd_id_q.size(); i++) begin
                        if (rd_id_q[i] == vif.rid) begin
                            rd_id_q.delete(i);
                            rd_slv_q.delete(i);
                            break;
                        end
                    end
                end

                // 3. 监测 W 突发中途气泡、W 反压及 B/R 响应反压
                if (vif.wvalid && vif.wready) begin
                    cur_w_pipe_state = W_BEAT_TRANSFER;
                    w_burst_busy     = !vif.wlast;
                    cur_b_backpressure = (vif.bvalid && !vif.bready);
                    cur_r_backpressure = (vif.rvalid && !vif.rready);
                    cg_axi_backpressure_data.sample();
                end else if (w_burst_busy && !vif.wvalid && vif.wready) begin
                    cur_w_pipe_state = W_MASTER_BUBBLE;
                    cur_b_backpressure = (vif.bvalid && !vif.bready);
                    cur_r_backpressure = (vif.rvalid && !vif.rready);
                    cg_axi_backpressure_data.sample();
                end else if (vif.wvalid && !vif.wready) begin
                    cur_w_pipe_state = W_SLAVE_STALL;
                    cur_b_backpressure = (vif.bvalid && !vif.bready);
                    cur_r_backpressure = (vif.rvalid && !vif.rready);
                    cg_axi_backpressure_data.sample();
                end else if ((vif.bvalid && !vif.bready) || (vif.rvalid && !vif.rready)) begin
                    cur_w_pipe_state   = W_BEAT_TRANSFER;
                    cur_b_backpressure = (vif.bvalid && !vif.bready);
                    cur_r_backpressure = (vif.rvalid && !vif.rready);
                    cg_axi_backpressure_data.sample();
                end
            end
        end
    endtask: monitor_pipeline_microarch

    virtual function void report_phase(uvm_phase phase);
        real pipe_cov;
        super.report_phase(phase);
        pipe_cov = (cg_axi_pipeline_addr.get_coverage() + cg_axi_backpressure_data.get_coverage()) / 2.0;

        `uvm_info("AXI_COV", "==========================================================", UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("1. 事务层数据切片与三维交叉覆盖率 : %0.2f%%", cg_axi_trans.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("2. 拓扑路由与四维单主状态跳转     : %0.2f%%", cg_axi_routing.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("3. 全双工读写同步并发仲裁覆盖率   : %0.2f%%", cg_axi_arbitration.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("4. 写通道首末拍精确时序交织       : %0.2f%%", cg_axi_handshake_timing.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("5. 微架构在途深度/ID冲突/反压气泡 : %0.2f%% (Addr:%0.2f%%, Data/Resp:%0.2f%%)",
                  pipe_cov, cg_axi_pipeline_addr.get_coverage(), cg_axi_backpressure_data.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", "==========================================================", UVM_LOW)
    endfunction: report_phase

endclass: axi_coverage

`endif // AXI_COVERAGE_SV

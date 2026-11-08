`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

// 声明独立的分析导出端口，避免与 Scoreboard 的 imp 宏冲突
`uvm_analysis_imp_decl(_cov_m0)
`uvm_analysis_imp_decl(_cov_m1)

class axi_coverage #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_component;

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // 双通道分析端口，分别对接 M0 和 M1 Monitor
    uvm_analysis_imp_cov_m0 #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH), axi_coverage #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)) analysis_export_m0;
    uvm_analysis_imp_cov_m1 #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH), axi_coverage #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)) analysis_export_m1;

    // 内部暂存对象
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr_sampled;
    bit cur_master_id; // 0 代表 Master 0, 1 代表 Master 1

    // ==============================================================
    // AXI4 功能覆盖组
    // ==============================================================
    covergroup axi_cov_grp;
        option.per_instance = 1;
        option.name = "AXI4_Interconnect_Coverage";

        // 1. 发起端主机覆盖
        cp_master: coverpoint cur_master_id {
            bins m0 = {1'b0};
            bins m1 = {1'b1};
        }

        // 2. 事务类型覆盖
        cp_trans_type: coverpoint tr_sampled.trans_type {
            bins write_trans = {AXI_WRITE};
            bins read_trans  = {AXI_READ};
        }

        // 3. 突发长度覆盖 (阶梯覆盖)
        cp_burst_len: coverpoint tr_sampled.len {
            bins single_beat = {8'd0};
            bins short_burst = {[8'd1 : 8'd3]};
            bins med_burst   = {[8'd4 : 8'd15]};
            bins long_burst  = {[8'd16 : 8'd31]}; // 支持 16~32 拍长突发
        }

        // 4. 突发位宽覆盖 (窄带与满位宽)
        cp_burst_size: coverpoint tr_sampled.size {
            bins byte_1  = {3'b000}; // 1 Byte
            bins byte_2  = {3'b001}; // 2 Bytes
            bins byte_4  = {3'b010}; // 4 Bytes
            bins byte_8  = {3'b011}; // 8 Bytes (64-bit)
            illegal_bins invalid_size = {[3'b100 : 3'b111]};
        }

        // 5. 突发模式
        cp_burst_type: coverpoint tr_sampled.burst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            ignore_bins wrap_ignore = {2'b10}; // SRAM 互联子系统不测试 WRAP
        }

        // 6. Crossbar 目标地址路由分布
        cp_addr_slave: coverpoint tr_sampled.addr {
            bins slave0_axi_ram  = {[32'h0000_0000 : 32'h0000_7FFF]}; // AXI 高速 RAM (32KB)
            bins slave1_axil_ram = {[32'h0001_0000 : 32'h0001_0FFF]}; // AXI-Lite RAM (4KB)
            bins unmapped_hole   = {[32'h0002_0000 : 32'h0002_FFFF]}; // 未映射孔洞 (激发 DECERR)
        }

        // 7. 写响应通道状态覆盖
        cp_bresp_status: coverpoint tr_sampled.bresp iff (tr_sampled.trans_type == AXI_WRITE) {
            bins okay   = {2'b00};
            bins decerr = {2'b11};
            ignore_bins exokay_ignore = {2'b01}; // 无排他监视器
            ignore_bins slverr_ignore = {2'b10};
        }

        // 8. 读响应通道状态覆盖
        cp_rresp_status: coverpoint tr_sampled.rresp iff (tr_sampled.trans_type == AXI_READ) {
            bins okay   = {2'b00};
            bins decerr = {2'b11};
            ignore_bins exokay_ignore = {2'b01};
            ignore_bins slverr_ignore = {2'b10};
        }

        // ==============================================================
        // 9. 核心交叉覆盖 (Cross Coverage)
        // ==============================================================
        
        // 核心一：全交叉路由矩阵 (M0/M1 必须均能对 S0/S1 执行读写)
        cross_matrix: cross cp_master, cp_addr_slave, cp_trans_type;

        // 核心二：突发尺寸与长度组合 (检验跨位宽长突发组合)
        cross_len_x_size: cross cp_burst_len, cp_burst_size;

        // 核心三：读写类型与长度组合
        cross_type_x_len: cross cp_trans_type, cp_burst_len;

    endgroup: axi_cov_grp

    `uvm_component_param_utils(axi_coverage #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        axi_cov_grp = new();
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export_m0 = new("analysis_export_m0", this);
        analysis_export_m1 = new("analysis_export_m1", this);
    endfunction: build_phase

    // M0 通道写入回调
    virtual function void write_cov_m0(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) t);
        this.tr_sampled    = t;
        this.cur_master_id = 1'b0;
        axi_cov_grp.sample();
    endfunction: write_cov_m0

    // M1 通道写入回调
    virtual function void write_cov_m1(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) t);
        this.tr_sampled    = t;
        this.cur_master_id = 1'b1;
        axi_cov_grp.sample();
    endfunction: write_cov_m1

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_COV", "==================================================", UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("AXI4 互联矩阵全覆盖率统计: %0.2f%%", axi_cov_grp.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", "==================================================", UVM_LOW)
    endfunction: report_phase

endclass: axi_coverage

`endif // AXI_COVERAGE_SV

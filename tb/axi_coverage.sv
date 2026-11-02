`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_coverage #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_subscriber #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // 内部暂存用于采样的事务对象句柄
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr_sampled;

    // ==============================================================
    // AXI4 功能覆盖组定义
    // ==============================================================
    covergroup axi_cov_grp;
        option.per_instance = 1; // 记录独立实例覆盖率
        option.name = "AXI4_Functional_Coverage";

        // 1. 事务类型覆盖：读 vs 写
        cp_trans_type: coverpoint tr_sampled.trans_type {
            bins write_trans = {AXI_WRITE};
            bins read_trans  = {AXI_READ};
        }

        // 2. 突发长度覆盖
        cp_burst_len: coverpoint tr_sampled.len {
            bins single_beat = {8'd0};
            bins short_burst = {[8'd1 : 8'd3]};
            bins med_burst   = {[8'd4 : 8'd15]};
            bins long_burst  = {[8'd16 : 8'd255]};
        }

        // 3. 突发大小覆盖 (每拍字节数)
        cp_burst_size: coverpoint tr_sampled.size {
            bins byte_1  = {3'b000}; // 1 Byte
            bins byte_2  = {3'b001}; // 2 Bytes
            bins byte_4  = {3'b010}; // 4 Bytes
            bins byte_8  = {3'b011}; // 8 Bytes (当前 64 位满总线)
            illegal_bins invalid_size = {[3'b100 : 3'b111]}; // 超过 64-bit 属非法配置
        }

        // 4. 突发类型覆盖
        cp_burst_type: coverpoint tr_sampled.burst {
            bins fixed = {2'b00}; // FIXED
            bins incr  = {2'b01}; // INCR (常规自增)
            bins wrap  = {2'b10}; // WRAP (回环)
        }

        // 5. Crossbar 目标地址路由分布
        cp_addr_slave: coverpoint tr_sampled.addr {
            bins slave0_axi_ram  = {[32'h0000_0000 : 32'h0000_7FFF]}; // AXI 高速 RAM
            bins slave1_axil_ram = {[32'h0001_0000 : 32'h0001_0FFF]}; // AXI-Lite RAM
            bins unmapped_space  = default;                            // 未映射孔洞
        }

        // 6. 响应状态覆盖
        cp_resp_status: coverpoint tr_sampled.bresp iff (tr_sampled.trans_type == AXI_WRITE) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }

        // ==============================================================
        // 7. 交叉覆盖 (Cross Coverage)
        // ==============================================================
        cross_type_x_len:   cross cp_trans_type, cp_burst_len;
        cross_slave_x_type: cross cp_addr_slave, cp_trans_type;
        cross_len_x_size:   cross cp_burst_len,  cp_burst_size;

    endgroup: axi_cov_grp

    `uvm_component_param_utils(axi_coverage #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_coverage", uvm_component parent = null);
        super.new(name, parent);
        axi_cov_grp = new(); // 实例化覆盖组
    endfunction: new

    // ==============================================================
    // 实现 uvm_subscriber 纯虚函数 write
    // ==============================================================
    virtual function void write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) t);
        this.tr_sampled = t;
        axi_cov_grp.sample();
    endfunction: write

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("AXI_COV", "==================================================", UVM_LOW)
        `uvm_info("AXI_COV", $sformatf("AXI4 功能覆盖率总计: %0.2f%%", axi_cov_grp.get_coverage()), UVM_LOW)
        `uvm_info("AXI_COV", "==================================================", UVM_LOW)
    endfunction: report_phase

endclass: axi_coverage

`endif // AXI_COVERAGE_SV

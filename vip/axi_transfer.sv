`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
} trans_type_e;

class axi_transfer #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) extends uvm_sequence_item;

    // 1. 协议核心随机字段
    rand trans_type_e          trans_type;
    rand bit [ID_WIDTH-1:0]    id;
    rand bit [ADDR_WIDTH-1:0]  addr;
    rand bit [7:0]             len;
    rand bit [2:0]             size;
    rand bit [1:0]             burst;
    rand bit                   lock;
    rand bit [3:0]             cache;
    rand bit [2:0]             prot;

    rand bit [DATA_WIDTH-1:0]  data[$];
    rand bit [STRB_WIDTH-1:0]  strb[$];

    // 2. 通道级时序偏斜随机字段 (单位：时钟周期)
    rand int unsigned          aw_delay;
    rand int unsigned          w_delay;
    rand bit                   w_insert_bubble; // 1: 在多拍 W 突发中间插入 wvalid 断流气泡

    // 3. 响应状态字段
    bit [1:0]                  bresp;
    bit [1:0]                  rresp;

    `uvm_object_param_utils_begin(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH))
        `uvm_field_enum(trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(id,         UVM_ALL_ON)
        `uvm_field_int(addr,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(len,        UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(size,       UVM_ALL_ON)
        `uvm_field_int(burst,      UVM_ALL_ON)
        `uvm_field_int(lock,       UVM_ALL_ON)
        `uvm_field_int(cache,      UVM_ALL_ON)
        `uvm_field_int(prot,       UVM_ALL_ON)
        `uvm_field_queue_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_queue_int(strb, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(aw_delay,   UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(w_delay,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(bresp,      UVM_ALL_ON)
        `uvm_field_int(rresp,      UVM_ALL_ON)
        `uvm_field_int(w_insert_bubble, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // ==============================================================
    // 约束 1: 数组结构与求解顺序硬约束
    // ==============================================================
    constraint c_struct_cfg {
        solve len before data, strb;
        data.size() == len + 1;
        strb.size() == len + 1;
    }

    // ==============================================================
    // 约束 2: AXI4 协议合规性约束 (4KB 边界与自然对齐)
    // ==============================================================
    constraint c_axi_protocol {
        solve size, len before addr;

        // 传输位宽不超过 64-bit 物理总线 (0:1B, 1:2B, 2:4B, 3:8B)
        size inside {[3'b000 : 3'b011]};

        // INCR 突发严禁跨越 4KB (13'h1000) 页面边界
        if (burst == 2'b01) {
            ((addr & 32'h0000_0FFF) + ((len + 1) << size)) <= 32'h0000_1000;
        }

        // 默认保持地址按传输位宽自然对齐 (匹配 coverage 中的 cross_size_x_offset)
        soft (addr & ((1 << size) - 1)) == 0;
    }

    // ==============================================================
    // 约束 3: 默认事务属性与权重分布软约束 (可被 Sequence 覆盖)
    // ==============================================================
    constraint c_default_cfg {
        soft burst == 2'b01; // 默认 INCR 突发
        // 允许 lock、cache、prot 随机翻转，覆盖 Crossbar 边带通路与保护属性分支
        soft lock  dist { 1'b0 := 90, 1'b1 := 10 };
        soft cache dist { 4'b0011 := 70, [4'b0000 : 4'b1111] := 30 };
        soft prot  dist { 3'b000  := 70, [3'b001  : 3'b111]  := 30 };

        soft len dist {
            8'd0          := 30,
            [8'd1 : 8'd3] := 30,
            [8'd4 : 8'd9] := 20,
            [8'd10: 8'd14]:= 10,
            8'd15         := 10
        };
    }

    // ==============================================================
    // 约束 4: 写通道 AW / W 握手偏斜随机分布
    // ==============================================================

    constraint c_timing_skew {
        soft aw_delay inside {[0 : 5]};
        soft w_delay  inside {[0 : 5]};

        // 保证至少一方为 0 基准，另一方在 0~5 拍内随机滑动（涵盖 1~2 拍译码对齐窗口）
        soft (aw_delay == 0) || (w_delay == 0);
        soft w_insert_bubble dist { 1'b1 := 30, 1'b0 := 70 };
    }

    function new(string name = "axi_transfer");
        super.new(name);
    endfunction: new

    // ==============================================================
    // post_randomize: 根据随机出的 addr 和 size 自动生成合法的 WSTRB
    // ==============================================================
    function void post_randomize();
        super.post_randomize();
        for (int b = 0; b <= len; b++) begin
            strb[b] = calc_strobe(addr, size, b);
        end
    endfunction: post_randomize

    function bit [STRB_WIDTH-1:0] calc_strobe(bit [ADDR_WIDTH-1:0] start_addr, bit [2:0] sz, int beat);
        bit [STRB_WIDTH-1:0] mask;
        bit [2:0]            offset;
        offset = (start_addr + (beat << sz)) & 3'b111;
        case (sz)
            3'b000:  mask = 8'h01 << offset;
            3'b001:  mask = 8'h03 << (offset & 3'b110);
            3'b010:  mask = 8'h0F << (offset & 3'b100);
            default: mask = 8'hFF;
        endcase
        return mask;
    endfunction: calc_strobe

endclass: axi_transfer

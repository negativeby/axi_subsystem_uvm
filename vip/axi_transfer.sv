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

    rand trans_type_e trans_type;

    rand bit [ID_WIDTH-1:0]   id;
    rand bit [ADDR_WIDTH-1:0] addr;
    rand bit [7:0]             len;
    rand bit [2:0]             size;
    rand bit [1:0]             burst;
    rand bit                   lock;
    rand bit [3:0]             cache;
    rand bit [2:0]             prot;

    rand bit [DATA_WIDTH-1:0] data[$];
    rand bit [STRB_WIDTH-1:0] strb[$];

    bit [1:0]                 bresp;
    bit [1:0]                 rresp;

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
        `uvm_field_queue_int(strb, UVM_ALL_ON)
        `uvm_field_int(bresp,      UVM_ALL_ON)
        `uvm_field_int(rresp,      UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_struct_cfg {
        data.size() == len + 1;
        strb.size() == len + 1;
    }

    // 核心重构: 将 soft 约束扩展至协议完整物理空间，避免对 sequence 的 hard dist 产生偏置截断
    constraint c_default_cfg {
        soft burst == 2'b01;
        soft size inside {[0 : 3]};   // 物理支持 1B, 2B, 4B, 8B
        soft len  inside {[0 : 31]};  // 物理支持 1~32 拍，覆盖 long_burst
        soft lock  == 1'b0;
        soft cache == 4'b0011;
        soft prot  == 3'b000;

        foreach (strb[i]) {
            soft strb[i] == {STRB_WIDTH{1'b1}};
        }
    }

    function new(string name = "axi_transfer");
        super.new(name);
    endfunction: new

endclass: axi_transfer

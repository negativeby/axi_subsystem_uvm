`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_transfer #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) extends uvm_sequence_item;

    // 1. 传输类型：读操作 (AXI_READ) 还是写操作 (AXI_WRITE)
    typedef enum bit { AXI_READ = 0, AXI_WRITE = 1 } trans_type_e;
    rand trans_type_e trans_type;

    // 2. 地址与突发控制属性 (对应物理总线上的 AW 与 AR 通道)
    rand bit [ID_WIDTH-1:0]    id;       // AXI ID，用于乱序和保序跟踪
    rand bit [ADDR_WIDTH-1:0]  addr;     // 起始访问地址
    rand bit [7:0]             len;      // 突发拍数 - 1 (协议规定：0代表1拍，3代表4拍)
    rand bit [2:0]             size;     // 每拍字节数 (3'b011 代表 2^3 = 8 字节 = 64 位)
    rand bit [1:0]             burst;    // 突发模式 (01 代表常用的地址自增模式 INCR)

    // 3. 数据载荷 (对应物理总线上的 W 通道和 R 通道)
    rand bit [DATA_WIDTH-1:0]  data[];   // 动态数组：存放每一拍的 64 位数据
    rand bit [STRB_WIDTH-1:0]  strb[];   // 动态数组：每一拍的字节使能掩码 (写通道专用)

    // 4. 传输结果回执 (对应物理总线上的 B 通道和 R 通道)
    bit [1:0]                  bresp;    // 写响应状态：00代表OKAY，非0代表出错
    bit [1:0]                  rresp[];  // 读响应状态：记录每一拍读数据的状态
    
    // 5. UVM 自动化宏 (注册所有变量，UVM 自动实现 print, copy, compare 等功能)
    `uvm_object_param_utils_begin(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH))
        `uvm_field_enum(trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(id,         UVM_ALL_ON)
        `uvm_field_int(addr,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(len,        UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(size,       UVM_ALL_ON)
        `uvm_field_int(burst,      UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(strb, UVM_ALL_ON)
        `uvm_field_int(bresp,      UVM_ALL_ON)
    `uvm_object_utils_end

    // 6. 基础合法性约束
    constraint c_default_cfg {
        // 模式固定为最常用的地址自增传输 (INCR)
        burst == 2'b01;

        // 每次访问大小匹配总线宽度 (64位总线 = 8字节 = 2^3，因此 size = 3)
        size == 3'b011;

        // 突发拍数限制在 1 ~ 16 拍之间 (便于刚开始看波形时数据不过长)
        len inside {[0:15]};

        // 核心约束：数据数组的大小必须严格等于实际突发拍数 (len + 1)
        data.size() == len + 1;
        strb.size() == len + 1;

        // 默认让所有字节使能有效 (64位里全部 8 个字节都写进去)
        foreach (strb[i]) {
            strb[i] == {STRB_WIDTH{1'b1}};
        }
    }

    // 构造函数
    function new(string name = "axi_transfer");
        super.new(name);
    endfunction

endclass: axi_transfer

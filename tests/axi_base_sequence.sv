`ifndef AXI_BASE_SEQUENCE_SV
`define AXI_BASE_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_base_sequence #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    `uvm_object_param_utils(axi_base_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_base_sequence");
        super.new(name);
    endfunction: new

    virtual task body();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr;
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_tr;

        `uvm_info("BASE_SEQ", "====== 冒烟测试序列启动: 发起 1 写 1 读 ======", UVM_LOW)

        // 1. 发起写事务 (向 axi_ram 地址 0x0000_1000 写入 2 拍 64-bit 数据)
        wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("wr_tr");
        start_item(wr_tr);
        wr_tr.trans_type = AXI_WRITE;
        wr_tr.addr       = 32'h0000_1000;
        wr_tr.len        = 8'd1;   // 1+1 = 2 拍
        wr_tr.size       = 3'b011; // 8 字节
        wr_tr.burst      = 2'b01;  // INCR
        wr_tr.id         = 8'h01;

        // 队列标准填充方式：使用 push_back 或队列字面量
        wr_tr.data.push_back(64'h1122_3344_5566_7788);
        wr_tr.strb.push_back({STRB_WIDTH{1'b1}});
        wr_tr.data.push_back(64'h99AA_BBCC_DDEE_FF00);
        wr_tr.strb.push_back({STRB_WIDTH{1'b1}});

        finish_item(wr_tr);
        `uvm_info("BASE_SEQ", "写事务已通过 Driver 注入总线并握手完毕", UVM_LOW)

        // 2. 发起读事务 (从相同地址 0x0000_1000 读回 2 拍)
        rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("rd_tr");
        start_item(rd_tr);
        rd_tr.trans_type = AXI_READ;
        rd_tr.addr       = 32'h0000_1000;
        rd_tr.len        = 8'd1;
        rd_tr.size       = 3'b011;
        rd_tr.burst      = 2'b01;
        rd_tr.id         = 8'h01;

        finish_item(rd_tr);
        `uvm_info("BASE_SEQ", "读事务已通过 Driver 注入总线并接收完毕", UVM_LOW)
    endtask: body

endclass: axi_base_sequence

`endif // AXI_BASE_SEQUENCE_SV

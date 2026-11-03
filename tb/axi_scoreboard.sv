`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_scoreboard #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_scoreboard;

    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam BYTES_PER_BEAT = DATA_WIDTH / 8;

    uvm_analysis_imp #(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH),
        axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)
    ) item_collected_export;

    // 黄金内存参考模型：按绝对物理字节地址索引的关联数组
    bit [7:0] golden_mem[bit [ADDR_WIDTH-1:0]];

    int unsigned write_trans_cnt = 0;
    int unsigned read_trans_cnt  = 0;
    int unsigned match_cnt       = 0;
    int unsigned mismatch_cnt    = 0;

    `uvm_component_param_utils(axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        item_collected_export = new("item_collected_export", this);
    endfunction: new

    virtual function void write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        if (tr.trans_type == AXI_WRITE) begin
            process_write(tr);
        end else if (tr.trans_type == AXI_READ) begin
            process_read(tr);
        end
    endfunction: write

    // ------------------------------------------------------------------
    // 处理写事务: 修复双重偏移 Bug，严谨映射物理总线字节通道
    // ------------------------------------------------------------------
    virtual function void process_write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        bit [ADDR_WIDTH-1:0] beat_addr;
        bit [ADDR_WIDTH-1:0] word_base_addr;
        int unsigned bytes_in_transfer = (1 << tr.size);

        write_trans_cnt++;

        for (int i = 0; i <= tr.len; i++) begin
            beat_addr      = tr.addr + (i * bytes_in_transfer);
            // 提取当前拍所在的 64-bit 对齐基地址 (低 3 位清零)
            word_base_addr = {beat_addr[ADDR_WIDTH-1:3], 3'b000};

            for (int b = 0; b < BYTES_PER_BEAT; b++) begin
                // 仅当该字节通道使能为 1 时，写入对应的绝对物理地址
                if (tr.strb[i][b]) begin
                    golden_mem[word_base_addr + b] = tr.data[i][(b*8) +: 8];
                end
            end
        end

        `uvm_info("SCB_WR", $sformatf("登记写事务: Addr=0x%08h, Len=%0d, Size=%0d", 
                  tr.addr, tr.len, tr.size), UVM_HIGH)
    endfunction: process_write

    // ------------------------------------------------------------------
    // 处理读事务: 仅对账 size 范围内有效字节通道，彻底消除窄传输假报错
    // ------------------------------------------------------------------
    virtual function void process_read(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        bit [ADDR_WIDTH-1:0] beat_addr;
        bit [ADDR_WIDTH-1:0] curr_byte_addr;
        bit [2:0] byte_lane;
        bit [7:0] exp_byte;
        bit [7:0] act_byte;
        bit       beat_error;
        int unsigned bytes_in_transfer = (1 << tr.size);

        read_trans_cnt++;

        for (int i = 0; i <= tr.len; i++) begin
            beat_addr  = tr.addr + (i * bytes_in_transfer);
            beat_error = 1'b0;

            // 仅遍历并比对当前拍真正被请求的有效字节 (2^size 字节)
            for (int k = 0; k < bytes_in_transfer; k++) begin
                curr_byte_addr = beat_addr + k;
                byte_lane      = curr_byte_addr[2:0]; // 确定该字节在 64 位总线上的物理通道

                if (golden_mem.exists(curr_byte_addr)) begin
                    exp_byte = golden_mem[curr_byte_addr];
                end else begin
                    exp_byte = 8'h00; // 未初始化物理空间默认为 0
                end

                act_byte = tr.data[i][(byte_lane * 8) +: 8];

                if (act_byte !== exp_byte) begin
                    beat_error = 1'b1;
                    `uvm_error("SCB_MISMATCH", $sformatf(
                        "数据不符! Beat[%0d] ByteAddr=0x%08h Lane=%0d | 期望值=0x%02h, 实际读出=0x%02h",
                        i, curr_byte_addr, byte_lane, exp_byte, act_byte
                    ))
                end
            end

            if (beat_error) begin
                mismatch_cnt++;
            end else begin
                match_cnt++;
            end
        end
    endfunction: process_read

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("总对账写事务数: %0d", write_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("总对账读事务数: %0d", read_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("比对成功拍数  : %0d", match_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("比对失败拍数  : %0d", mismatch_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)

        if (mismatch_cnt > 0) begin
            `uvm_fatal("SCB_FAIL", $sformatf("仿真结束核验失败! 共有 %0d 拍数据不匹配!", mismatch_cnt))
        end
    endfunction: check_phase

endclass: axi_scoreboard

`endif // AXI_SCOREBOARD_SV

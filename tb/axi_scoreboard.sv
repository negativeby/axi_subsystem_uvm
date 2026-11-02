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

    // 声明 TLM 接收端口 (Imp)
    // 模板参数 1: 传输的事务类型
    // 模板参数 2: 实现 write 方法的宿主类 (即当前 Scoreboard 自身)
    uvm_analysis_imp #(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH),
        axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)
    ) item_collected_export;

    // 黄金参考模型：按字节寻址的稀疏关联数组
    bit [7:0] golden_mem[bit [ADDR_WIDTH-1:0]];

    // 统计计数器
    int unsigned write_trans_cnt = 0;
    int unsigned read_trans_cnt  = 0;
    int unsigned match_cnt       = 0;
    int unsigned mismatch_cnt    = 0;

    `uvm_component_param_utils(axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        item_collected_export = new("item_collected_export", this);
    endfunction: new

    // ==============================================================
    // TLM 回调函数：只要 Monitor 发送 write(tr)，本函数立即被触发
    // ==============================================================
    virtual function void write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        if (tr.trans_type == AXI_WRITE) begin
            process_write(tr);
        end else if (tr.trans_type == AXI_READ) begin
            process_read(tr);
        end
    endfunction: write

    // 处理写事务：按拍解析字节地址，结合 wstrb 写入 Golden Memory
    virtual function void process_write(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        bit [ADDR_WIDTH-1:0] beat_addr;
        int unsigned bytes_in_transfer = (1 << tr.size);

        write_trans_cnt++;

        for (int i = 0; i <= tr.len; i++) begin
            // 简化的 INCR 模式地址递增推导
            beat_addr = tr.addr + (i * bytes_in_transfer);

            for (int b = 0; b < BYTES_PER_BEAT; b++) begin
                // 仅当对应的字节选通掩码有效时，才更新对应字节
                if (tr.strb[i][b]) begin
                    golden_mem[beat_addr + b] = tr.data[i][(b*8) +: 8];
                end
            end
        end

        `uvm_info("SCB_WR", $sformatf("成功登记写事务: Addr=0x%08h, Len=%0d, 写入数据拍数=%0d", 
                  tr.addr, tr.len, tr.data.size()), UVM_HIGH)
    endfunction: process_write

    // 处理读事务：从 Golden Memory 提取期望值，与 DUT 返回的 rdata 逐拍对比
    virtual function void process_read(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        bit [ADDR_WIDTH-1:0] beat_addr;
        bit [DATA_WIDTH-1:0] expected_data;
        bit [7:0] exp_byte;
        int unsigned bytes_in_transfer = (1 << tr.size);

        read_trans_cnt++;

        for (int i = 0; i <= tr.len; i++) begin
            beat_addr = tr.addr + (i * bytes_in_transfer);
            expected_data = '0;

            // 从关联数组中拼装出整拍数据
            for (int b = 0; b < BYTES_PER_BEAT; b++) begin
                if (golden_mem.exists(beat_addr + b)) begin
                    exp_byte = golden_mem[beat_addr + b];
                end else begin
                    exp_byte = 8'h00; // 硬件未初始化内存默认读回 0
                end
                expected_data[(b*8) +: 8] = exp_byte;
            end

            // 核心对账比对
            if (tr.data[i] !== expected_data) begin
                mismatch_cnt++;
                `uvm_error("SCB_MISMATCH", $sformatf(
                    "数据比对不符! Beat[%0d] Addr=0x%08h | 期望值(Golden)=0x%016h, 实际值(DUT)=0x%016h",
                    i, beat_addr, expected_data, tr.data[i]
                ))
            end else begin
                match_cnt++;
                `uvm_info("SCB_MATCH", $sformatf(
                    "数据比对吻合: Beat[%0d] Addr=0x%08h Data=0x%016h", 
                    i, beat_addr, tr.data[i]
                ), UVM_HIGH)
            end
        end
    endfunction: process_read

    // ==============================================================
    // check_phase: 仿真结束前做统计汇总与断言核验
    // ==============================================================
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

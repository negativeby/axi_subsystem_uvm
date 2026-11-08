`ifndef AXI_PINGPONG_SEQUENCE_SV
`define AXI_PINGPONG_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_pingpong_sequence #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_object_param_utils(axi_pingpong_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    // 内存缓冲区基地址
    localparam bit [31:0] BUF_A_BASE = 32'h0000_0000;
    localparam bit [31:0] BUF_B_BASE = 32'h0000_2000;
    localparam int unsigned TRANS_PER_BUFFER = 20;

    int unsigned max_outstanding = 4;
    semaphore sem;

    function new(string name = "axi_pingpong_sequence");
        super.new(name);
    endfunction: new

    // 线程安全的后台响应回收与令牌归还
    virtual task automatic wait_and_release(int unsigned tr_id);
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rsp_tr;
        get_response(rsp_tr, tr_id);
        sem.put(1);
    endtask: wait_and_release

    // 发起一组定向写流
    virtual task automatic write_stream(bit [31:0] base_addr, string tag);
        for (int i = 0; i < TRANS_PER_BUFFER; i++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rsp_tr;
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("%s_wr_%0d", tag, i));
            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01;
                size       == 3'b011; // 8 字节 (64-bit 满位宽)
                len        == 8'd0;   // 单拍精准对齐
                addr       == (base_addr + (i * 8));
            }) `uvm_fatal(get_type_name(), "写事务随机化失败！")

            for (int k = 0; k <= wr_tr.len; k++) wr_tr.strb[k] = 8'hFF;
            finish_item(wr_tr);
            get_response(rsp_tr, wr_tr.get_transaction_id());
        end
    endtask: write_stream

    // 发起一组带滑动窗口的多 Outstanding 读流
    virtual task automatic read_stream(bit [31:0] base_addr, string tag);
        for (int j = 0; j < TRANS_PER_BUFFER; j++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_tr;
            rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("%s_rd_%0d", tag, j));

            sem.get(1); // 索要滑动窗口令牌

            start_item(rd_tr);
            if (!rd_tr.randomize() with {
                trans_type == AXI_READ;
                burst      == 2'b01;
                size       == 3'b011;
                len        == 8'd0;
                addr       == (base_addr + (j * 8));
            }) `uvm_fatal(get_type_name(), "读事务随机化失败！")

            fork
                wait_and_release(rd_tr.get_transaction_id());
            join_none

            finish_item(rd_tr);
        end

        // 窗口排空：确保当前缓冲区的所有读数据完全接收完毕
        sem.get(max_outstanding);
        sem.put(max_outstanding);
    endtask: read_stream

    virtual task body();
        `uvm_info(get_type_name(), "====== 启动 AXI 双缓冲乒乓翻转全双工边写边读测试 ======", UVM_LOW)

        sem = new(max_outstanding);

        // 阶段 0: 预热 Buffer A
        `uvm_info(get_type_name(), "阶段 0: 预热写入 Buffer A (0x0000_0000) 建立第一棒基准底账...", UVM_LOW)
        write_stream(BUF_A_BASE, "warmup_A");

        // 阶段 1: 乒乓轮次 1 (写 Buffer B 同时读 Buffer A)
        `uvm_info(get_type_name(), "阶段 1: 启动第一轮对轰 —— [写 Buffer B] || [读 Buffer A]...", UVM_LOW)
        fork
            write_stream(BUF_B_BASE, "round1_B");
            read_stream(BUF_A_BASE, "round1_A");
        join

        // 阶段 2: 乒乓翻转轮次 2 (写 Buffer A 同时读【阶段 1 刚写入的 Buffer B】)
        `uvm_info(get_type_name(), "阶段 2: 翻转执行第二轮对轰 —— [写 Buffer A] || [读回 Buffer B 刚写入的数据]...", UVM_LOW)
        fork
            write_stream(BUF_A_BASE, "round2_A");
            read_stream(BUF_B_BASE, "round2_B");
        join

        // 阶段 3: 最终收尾验证 (将阶段 2 写入 Buffer A 的数据读出对账闭环)
        `uvm_info(get_type_name(), "阶段 3: 收尾回读 Buffer A 刚覆写的数据，确保全局无遗留盲区...", UVM_LOW)
        read_stream(BUF_A_BASE, "final_A");

        `uvm_info(get_type_name(), "====== AXI 乒乓边写边读全闭环验证顺利完成 ======", UVM_LOW)
    endtask: body

endclass: axi_pingpong_sequence

`endif // AXI_PINGPONG_SEQUENCE_SV

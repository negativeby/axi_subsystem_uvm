`ifndef AXI_OUTSTANDING_SEQUENCE_SV
`define AXI_OUTSTANDING_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_outstanding_sequence #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_object_param_utils(axi_outstanding_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    // 核心参数: 允许的最大在途未决事务深度
    int unsigned max_outstanding = 4;
    int unsigned num_trans       = 50;

    // 滑动窗口信号量
    semaphore sem;

    function new(string name = "axi_outstanding_sequence");
        super.new(name);
    endfunction: new

    // 线程安全的后台响应回收与令牌归还任务
    virtual task automatic wait_and_release(int unsigned tr_id);
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rsp_tr;
        get_response(rsp_tr, tr_id);
        sem.put(1);
    endtask: wait_and_release

    virtual task body();
        `uvm_info(get_type_name(), "====== 启动 AXI 多 Outstanding (深度=4) 地址流水压力测试 ======", UVM_LOW)

        sem = new(max_outstanding);

        // 阶段 1: 预热写入 Slave 0 (AXI RAM) 连续存储块
        `uvm_info(get_type_name(), "阶段 1: 预热写入 16 个地址块建立参考底账...", UVM_LOW)
        for (int p = 0; p < 16; p++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rsp_tr;
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("init_wr_%0d", p));
            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01;
                size       == 3'b011; // 8 字节满位宽
                len        == 8'd0;   // 单拍
                addr       == (32'h0000_0000 + (p * 8));
            }) `uvm_fatal(get_type_name(), "预热写随机失败！")
            for (int k = 0; k <= wr_tr.len; k++) wr_tr.strb[k] = 8'hFF;
            finish_item(wr_tr);
            get_response(rsp_tr, wr_tr.get_transaction_id());
        end

        // 阶段 2: 启动滑动窗口多 Outstanding 读地址流水狂轰
        `uvm_info(get_type_name(), $sformatf("阶段 2: 注入 50 笔读流，锁定最大在途深度=%0d...", max_outstanding), UVM_LOW)
        for (int i = 0; i < num_trans; i++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_tr;
            rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("ot_rd_%0d", i));

            // 1. 获取滑动窗口令牌 (若已达深度上限则挂起等待)
            sem.get(1);

            start_item(rd_tr);
            if (!rd_tr.randomize() with {
                trans_type == AXI_READ;
                burst      == 2'b01;
                size       == 3'b011;
                len        inside {[0 : 3]}; // 1~4 拍
                addr       inside {[32'h0000_0000 : 32'h0000_0078]}; // 命中预热空间
                addr % 8   == 0;
                (addr[11:0] + ((len + 1) << size)) <= 4096;
            }) `uvm_fatal(get_type_name(), "Outstanding 读事务随机失败！")

            // 2. 派发后台监听微线程，负责接收该事务完成并归还令牌
            fork
                wait_and_release(rd_tr.get_transaction_id());
            join_none

            // 3. 将事务交付 Driver，立即进入下一轮循环！
            finish_item(rd_tr);
        end

        // 阶段 3: 等待所有在途未决事务排空归还
        `uvm_info(get_type_name(), "阶段 3: 发射完成，等待所有 Outstanding 事务在途排空...", UVM_LOW)
        sem.get(max_outstanding);
        sem.put(max_outstanding);

        `uvm_info(get_type_name(), "====== AXI 多 Outstanding 压力测试顺利完成 ======", UVM_LOW)
    endtask: body

endclass: axi_outstanding_sequence

`endif // AXI_OUTSTANDING_SEQUENCE_SV

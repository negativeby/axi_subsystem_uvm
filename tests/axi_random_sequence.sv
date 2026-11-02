`ifndef AXI_RANDOM_SEQUENCE_SV
`define AXI_RANDOM_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_random_sequence #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_object_param_utils(axi_random_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    int unsigned num_trans = 100; // 提升至 100 轮 (200 笔写读)，加速交叉覆盖收敛

    function new(string name = "axi_random_sequence");
        super.new(name);
    endfunction: new

    virtual task body();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rd_tr;

        `uvm_info(get_type_name(), $sformatf("====== 启动增强随机序列: 注入 %0d 轮多尺寸/长突发写读 ======", num_trans), UVM_LOW)

        for (int i = 0; i < num_trans; i++) begin
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("wr_tr_%0d", i));
            start_item(wr_tr);

            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01; // INCR 突发

                // 1. 窄传输全面放开: 0=1B, 1=2B, 2=4B, 3=8B
                size inside {[0 : 3]};

                // 2. 突发长度覆盖长突发 (0~31)
                len inside {[0 : 31]};

                // 3. 从机访问概率对半均分 (权重 50:50)
                addr inside {
                    [32'h0000_0000 : 32'h0000_7FFF], // Slave 0: AXI RAM
                    [32'h0001_0000 : 32'h0001_0FFF]  // Slave 1: AXIL RAM
                };
                (addr >= 32'h0001_0000) dist { 1 := 50, 0 := 50 };

                // 4. 地址按当前 size 自然对齐
                addr % (1 << size) == 0;

                // 5. AXI 严禁跨越 4KB 边界约束
                (addr[11:0] + ((len + 1) << size)) <= 4096;
            }) begin
                `uvm_fatal(get_type_name(), "写事务随机化失败！")
            end

            finish_item(wr_tr);

            // 镜像读事务
            rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("rd_tr_%0d", i));
            start_item(rd_tr);

            if (!rd_tr.randomize() with {
                trans_type == AXI_READ;
                burst      == wr_tr.burst;
                addr       == wr_tr.addr;
                len        == wr_tr.len;
                size       == wr_tr.size;
            }) begin
                `uvm_fatal(get_type_name(), "读事务随机化失败！")
            end

            finish_item(rd_tr);
        end

        `uvm_info(get_type_name(), "====== 增强随机序列执行完毕 ======", UVM_LOW)
    endtask: body

endclass: axi_random_sequence

`endif // AXI_RANDOM_SEQUENCE_SV

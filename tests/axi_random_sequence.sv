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

    int unsigned num_trans = 100;

    function new(string name = "axi_random_sequence");
        super.new(name);
    endfunction: new

    function bit [(DATA_WIDTH/8)-1:0] calc_wstrb(bit [ADDR_WIDTH-1:0] base_addr, bit [2:0] burst_size, int beat_idx);
        bit [ADDR_WIDTH-1:0] current_addr;
        bit [2:0] byte_offset;
        bit [(DATA_WIDTH/8)-1:0] mask;
        int num_bytes;

        current_addr = base_addr + (beat_idx * (1 << burst_size));
        byte_offset  = current_addr[2:0];
        num_bytes    = (1 << burst_size);

        mask = '0;
        for (int b = 0; b < num_bytes; b++) begin
            if ((byte_offset + b) < (DATA_WIDTH/8)) begin
                mask[byte_offset + b] = 1'b1;
            end
        end
        return mask;
    endfunction: calc_wstrb

    virtual task body();
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rd_tr;

        `uvm_info(get_type_name(), $sformatf("====== 启动修复版随机序列: 注入 %0d 轮写读 ======", num_trans), UVM_LOW)

        for (int i = 0; i < num_trans; i++) begin
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("wr_tr_%0d", i));
            start_item(wr_tr);

            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01;

                // 尺寸均分 (各 25%)
                size dist { 0 := 25, 1 := 25, 2 := 25, 3 := 25 };

                // 核心修复: 使用 :/ 均分区间权重，确保 single_beat(0) 占满 25% 概率
                len dist {
                    0          := 25,
                    [1  : 3]   :/ 25,
                    [4  : 15]  :/ 25,
                    [16 : 31]  :/ 25
                };

                addr inside {
                    [32'h0000_0000 : 32'h0000_7FFF], // Slave 0: AXI RAM
                    [32'h0001_0000 : 32'h0001_0FFF]  // Slave 1: AXIL RAM
                };
                (addr >= 32'h0001_0000) dist { 1 := 50, 0 := 50 };

                addr % (1 << size) == 0;
                (addr[11:0] + ((len + 1) << size)) <= 4096;
            }) begin
                `uvm_fatal(get_type_name(), "写事务随机化失败！")
            end

            for (int k = 0; k <= wr_tr.len; k++) begin
                wr_tr.strb[k] = calc_wstrb(wr_tr.addr, wr_tr.size, k);
            end

            finish_item(wr_tr);

            // 发起镜像读事务
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

        `uvm_info(get_type_name(), "====== 修复版随机序列执行完毕 ======", UVM_LOW)
    endtask: body

endclass: axi_random_sequence

`endif // AXI_RANDOM_SEQUENCE_SV

`ifndef AXI_ADAPTER_SEQUENCE_SV
`define AXI_ADAPTER_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_adapter_sequence #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_object_param_utils(axi_adapter_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    localparam bit [31:0] SLAVE1_BASE = 32'h0001_0000;
    localparam bit [31:0] SLAVE1_TOP  = 32'h0001_0FFF;

    int unsigned num_trans = 30;

    // 存储写入记录，供后续精确回读
    axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_records[$];

    function new(string name = "axi_adapter_sequence");
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
        `uvm_info(get_type_name(), "====== 启动 AXI-Lite 适配桥长突发拆解/拼装压测 ======", UVM_LOW)

        // 阶段 1: 向 Slave 1 连续注入多拍突发写 (强制 len >= 1)
        `uvm_info(get_type_name(), "阶段 1: 注入多拍长突发写，压测适配桥写拆解与 AXI-Lite 串行化...", UVM_LOW)
        for (int i = 0; i < num_trans; i++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rsp_tr;
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("axil_wr_%0d", i));

            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01;                // INCR 突发
                size inside {[1 : 3]};              // 2/4/8 字节
                len  inside {[1 : 7]};              // 强制 2~8 拍长突发，触发拆包
                addr inside {[SLAVE1_BASE : (SLAVE1_TOP - 64)]};
                addr % (1 << size) == 0;
                (addr[11:0] + ((len + 1) << size)) <= 4096; // 4KB 边界保护
            }) `uvm_fatal(get_type_name(), "Slave 1 突发写随机化失败！")

            for (int k = 0; k <= wr_tr.len; k++) begin
                wr_tr.strb[k] = calc_wstrb(wr_tr.addr, wr_tr.size, k);
            end

            finish_item(wr_tr);
            get_response(rsp_tr, wr_tr.get_transaction_id());

            // 存入账本，供阶段 2 对称回读
            wr_records.push_back(wr_tr);
        end

        `uvm_info(get_type_name(), "写突发注入完毕，等待总线静默...", UVM_LOW)
        #100ns;

        // 阶段 2: 按相同属性回读 Slave 1，压测适配桥读重组与拼装
        `uvm_info(get_type_name(), "阶段 2: 注入对应长突发读，压测适配桥读重组与 RLAST 补齐...", UVM_LOW)
        for (int j = 0; j < wr_records.size(); j++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_tr, rsp_tr;
            rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("axil_rd_%0d", j));

            start_item(rd_tr);
            // 镜像构造与写入完全一致的读请求
            rd_tr.trans_type = AXI_READ;
            rd_tr.addr       = wr_records[j].addr;
            rd_tr.burst      = wr_records[j].burst;
            rd_tr.size       = wr_records[j].size;
            rd_tr.len        = wr_records[j].len;
            rd_tr.lock       = '0;
            rd_tr.cache      = '0;
            rd_tr.prot       = '0;
            rd_tr.id         = j[ID_WIDTH-1:0];

            finish_item(rd_tr);
            get_response(rsp_tr, rd_tr.get_transaction_id());
        end

        `uvm_info(get_type_name(), "====== AXI-Lite 适配桥长突发压测序列完成 ======", UVM_LOW)
    endtask: body

endclass: axi_adapter_sequence

`endif // AXI_ADAPTER_SEQUENCE_SV

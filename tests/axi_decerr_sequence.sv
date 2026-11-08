`ifndef AXI_DECERR_SEQUENCE_SV
`define AXI_DECERR_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class axi_decerr_sequence #(
    int ADDR_WIDTH = 32,
    int DATA_WIDTH = 64,
    int ID_WIDTH   = 8
) extends uvm_sequence #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_object_param_utils(axi_decerr_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    int unsigned num_err_trans = 20;

    function new(string name = "axi_decerr_sequence");
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
        `uvm_info(get_type_name(), "====== 启动 AXI 地址空洞 DECERR 异常注入压测 ======", UVM_LOW)

        // 阶段 1: 向空洞地址注入非法写事务
        `uvm_info(get_type_name(), "阶段 1: 注入非法地址写，检验 Crossbar 默认从机回吐 BRESP=DECERR...", UVM_LOW)
        for (int i = 0; i < num_err_trans; i++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) wr_tr, rsp_tr;
            wr_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("err_wr_%0d", i));

            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                trans_type == AXI_WRITE;
                burst      == 2'b01;
                size inside {[1 : 3]};
                len  inside {[0 : 3]};
                // 约束命中两个未映射空洞区间之一
                addr inside {
                    [32'h0000_8000 : 32'h0000_F000],
                    [32'h0001_1000 : 32'h0001_F000]
                };
                addr % (1 << size) == 0;
            }) `uvm_fatal(get_type_name(), "非法地址写事务随机化失败！")

            for (int k = 0; k <= wr_tr.len; k++) begin
                wr_tr.strb[k] = calc_wstrb(wr_tr.addr, wr_tr.size, k);
            end

            finish_item(wr_tr);
            get_response(rsp_tr, wr_tr.get_transaction_id());

            `uvm_info(get_type_name(), $sformatf("完成非法写: Addr=0x%08h, BRESP=2'b%02b", wr_tr.addr, rsp_tr.bresp), UVM_HIGH)
        end

        #100ns;

        // 阶段 2: 向空洞地址注入非法读事务
        `uvm_info(get_type_name(), "阶段 2: 注入非法地址读，检验 Crossbar 默认从机回吐 RRESP=DECERR...", UVM_LOW)
        for (int j = 0; j < num_err_trans; j++) begin
            axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rd_tr, rsp_tr;
            rd_tr = axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create($sformatf("err_rd_%0d", j));

            start_item(rd_tr);
            if (!rd_tr.randomize() with {
                trans_type == AXI_READ;
                burst      == 2'b01;
                size inside {[1 : 3]};
                len  inside {[0 : 3]};
                addr inside {
                    [32'h0000_8000 : 32'h0000_F000],
                    [32'h0001_1000 : 32'h0001_F000]
                };
                addr % (1 << size) == 0;
            }) `uvm_fatal(get_type_name(), "非法地址读事务随机化失败！")

            finish_item(rd_tr);
            get_response(rsp_tr, rd_tr.get_transaction_id());

            `uvm_info(get_type_name(), $sformatf("完成非法读: Addr=0x%08h, RRESP=2'b%02b", rd_tr.addr, rsp_tr.rresp), UVM_HIGH)
        end

        `uvm_info(get_type_name(), "====== AXI 地址空洞 DECERR 异常注入全部完成 ======", UVM_LOW)
    endtask: body

endclass: axi_decerr_sequence

`endif // AXI_DECERR_SEQUENCE_SV

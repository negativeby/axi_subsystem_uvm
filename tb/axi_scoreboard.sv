`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

// ==============================================================
// 声明双通道 Analysis Imp 宏 (必须置于类定义外部)
// ==============================================================
`uvm_analysis_imp_decl(_m0)
`uvm_analysis_imp_decl(_m1)

class axi_scoreboard #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8
) extends uvm_scoreboard;

    localparam int STRB_WIDTH     = DATA_WIDTH / 8;
    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;

    // Master 0 (VIP) 监控导出端口
    uvm_analysis_imp_m0 #(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH),
        axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)
    ) item_collected_export_m0;

    // Master 1 (DMA) 监控导出端口
    uvm_analysis_imp_m1 #(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH),
        axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)
    ) item_collected_export_m1;

    // 黄金内存参考模型 (按 Byte 寻址)
    bit [7:0] golden_mem[bit [ADDR_WIDTH-1:0]];

    // 统计度量计数器
    int unsigned m0_write_trans_cnt = 0;
    int unsigned m0_read_trans_cnt  = 0;
    int unsigned m1_write_trans_cnt = 0;
    int unsigned m1_read_trans_cnt  = 0;

    int unsigned match_cnt          = 0;
    int unsigned mismatch_cnt       = 0;
    int unsigned decerr_match_cnt   = 0;
    int unsigned resp_error_cnt     = 0;

    `uvm_component_param_utils(axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        item_collected_export_m0 = new("item_collected_export_m0", this);
        item_collected_export_m1 = new("item_collected_export_m1", this);
    endfunction: new

    // 地址译码判断
    function bit is_mapped_addr(bit [ADDR_WIDTH-1:0] addr);
        // Slave 0: AXI RAM (32KB: 0x0000_0000 ~ 0x0000_7FFF)
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_7FFF) return 1'b1;
        // Slave 1: AXIL RAM (4KB: 0x0001_0000 ~ 0x0001_0FFF)
        if (addr >= 32'h0001_0000 && addr <= 32'h0001_0FFF) return 1'b1;
        return 1'b0;
    endfunction: is_mapped_addr

    // ==============================================================
    // Master 0 (VIP) 事务入口
    // ==============================================================
    virtual function void write_m0(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        if (tr.trans_type == AXI_WRITE) begin
            m0_write_trans_cnt++;
            process_write(tr, "M0_VIP");
        end else if (tr.trans_type == AXI_READ) begin
            m0_read_trans_cnt++;
            process_read(tr, "M0_VIP");
        end
    endfunction: write_m0

    // ==============================================================
    // Master 1 (DMA) 事务入口
    // ==============================================================
    virtual function void write_m1(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr);
        if (tr.trans_type == AXI_WRITE) begin
            m1_write_trans_cnt++;
            process_write(tr, "M1_DMA");
        end else if (tr.trans_type == AXI_READ) begin
            m1_read_trans_cnt++;
            process_read(tr, "M1_DMA");
        end
    endfunction: write_m1

    // ==============================================================
    // 通用写处理流水线
    // ==============================================================
    virtual function void process_write(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr,
        string tag
    );
        bit [ADDR_WIDTH-1:0] beat_addr;
        bit [ADDR_WIDTH-1:0] word_base_addr;
        int unsigned bytes_in_transfer = (1 << tr.size);
        bit legal = is_mapped_addr(tr.addr);

        if (legal) begin
            if (tr.bresp !== 2'b00) begin
                resp_error_cnt++;
                `uvm_error("SCB_RESP_ERR", $sformatf("[%s] 合法写响应异常! Addr=0x%08h, 期望 BRESP=2'b00, 实际=2'b%02b", tag, tr.addr, tr.bresp))
            end

            // 依据实际总线采样的写数据和掩码更新参考模型
            for (int i = 0; i <= tr.len; i++) begin
                beat_addr      = tr.addr + (i * bytes_in_transfer);
                word_base_addr = {beat_addr[ADDR_WIDTH-1:3], 3'b000};

                for (int b = 0; b < BYTES_PER_BEAT; b++) begin
                    if (tr.strb[i][b]) begin
                        golden_mem[word_base_addr + b] = tr.data[i][(b*8) +: 8];
                    end
                end
            end
            `uvm_info("SCB_WR_TR", $sformatf("[%s] 写参考模型更新: Addr=0x%08h, Len=%0d, Size=%0d", tag, tr.addr, tr.len, tr.size), UVM_HIGH)
        end else begin
            // 空洞写必须由从机/Crossbar 吞噬并回吐 DECERR
            if (tr.bresp === 2'b11) begin
                decerr_match_cnt++;
                `uvm_info("SCB_DECERR_OK", $sformatf("[%s] 成功捕获写空洞 DECERR 响应: Addr=0x%08h", tag, tr.addr), UVM_HIGH)
            end else begin
                resp_error_cnt++;
                `uvm_error("SCB_DECERR_FAIL", $sformatf("[%s] 空洞写未返回 DECERR! Addr=0x%08h, 实际 BRESP=2'b%02b", tag, tr.addr, tr.bresp))
            end
        end
    endfunction: process_write

    // ==============================================================
    // 通用读比对流水线
    // ==============================================================
    virtual function void process_read(
        axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) tr,
        string tag
    );
        bit [ADDR_WIDTH-1:0] beat_addr;
        bit [ADDR_WIDTH-1:0] curr_byte_addr;
        bit [2:0]            byte_lane;
        bit [7:0]            exp_byte;
        bit [7:0]            act_byte;
        bit                  beat_error;
        int unsigned bytes_in_transfer = (1 << tr.size);
        bit legal = is_mapped_addr(tr.addr);

        if (legal) begin
            if (tr.rresp !== 2'b00) begin
                resp_error_cnt++;
                `uvm_error("SCB_RESP_ERR", $sformatf("[%s] 合法读响应异常! Addr=0x%08h, 期望 RRESP=2'b00, 实际=2'b%02b", tag, tr.addr, tr.rresp))
            end

            for (int i = 0; i <= tr.len; i++) begin
                beat_addr  = tr.addr + (i * bytes_in_transfer);
                beat_error = 1'b0;

                for (int k = 0; k < bytes_in_transfer; k++) begin
                    curr_byte_addr = beat_addr + k;
                    byte_lane      = curr_byte_addr[2:0];

                    if (golden_mem.exists(curr_byte_addr)) begin
                        exp_byte = golden_mem[curr_byte_addr];
                    end else begin
                        exp_byte = 8'h00;
                    end

                    act_byte = tr.data[i][(byte_lane * 8) +: 8];

                    if (act_byte !== exp_byte) begin
                        beat_error = 1'b1;
                        `uvm_error("SCB_MISMATCH", $sformatf(
                            "[%s] 数据不符! Beat[%0d] ByteAddr=0x%08h Lane=%0d | 期望值=0x%02h, 实际读出=0x%02h",
                            tag, i, curr_byte_addr, byte_lane, exp_byte, act_byte
                        ))
                    end
                end

                if (beat_error) begin
                    mismatch_cnt++;
                end else begin
                    match_cnt++;
                end
            end
        end else begin
            // 空洞读必须返回 DECERR
            if (tr.rresp === 2'b11) begin
                decerr_match_cnt++;
                `uvm_info("SCB_DECERR_OK", $sformatf("[%s] 成功捕获读空洞 DECERR 响应: Addr=0x%08h", tag, tr.addr), UVM_HIGH)
            end else begin
                resp_error_cnt++;
                `uvm_error("SCB_DECERR_FAIL", $sformatf("[%s] 空洞读未返回 DECERR! Addr=0x%08h, 实际 RRESP=2'b%02b", tag, tr.addr, tr.rresp))
            end
        end
    endfunction: process_read

    // ==============================================================
    // 仿真结束汇总核验
    // ==============================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("Master 0 (VIP) 写事务数  : %0d", m0_write_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("Master 0 (VIP) 读事务数  : %0d", m0_read_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("Master 1 (DMA) 写事务数  : %0d", m1_write_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("Master 1 (DMA) 读事务数  : %0d", m1_read_trans_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("正常数据比对成功拍数     : %0d", match_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("正常数据比对失败拍数     : %0d", mismatch_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("DECERR 正确响应捕获数    : %0d", decerr_match_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", $sformatf("协议响应状态码错误数     : %0d", resp_error_cnt), UVM_LOW)
        `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)

        if (mismatch_cnt > 0 || resp_error_cnt > 0) begin
            `uvm_fatal("SCB_FAIL", "仿真结束核验失败! 存在数据不符或协议响应异常!")
        end
    endfunction: check_phase

endclass: axi_scoreboard

`endif // AXI_SCOREBOARD_SV

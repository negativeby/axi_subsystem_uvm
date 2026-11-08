`ifndef CONCURRENT_TEST_SV
`define CONCURRENT_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

`include "axi_concurrent_sequence.sv"

class concurrent_test extends base_test;

    `uvm_component_utils(concurrent_test)

    function new(string name = "concurrent_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_dual_master_vseq vseq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(), "====== concurrent_test 启动 (纯双主 VIP 架构) ======", UVM_LOW)
        wait(tb_top.rst_n === 1'b1);
        @(posedge tb_top.clk);

        vseq = axi_dual_master_vseq::type_id::create("vseq");
        // 将环境中的两路物理 Sequencer 句柄注入 Virtual Sequence
        vseq.m0_sqr = env.m0_agent.sqr;
        vseq.m1_sqr = env.m1_agent.sqr;
        vseq.start(null);

        #300ns;
        `uvm_info(get_type_name(), "====== concurrent_test 执行完毕，退出仿真 ======", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: concurrent_test

`endif // CONCURRENT_TEST_SV

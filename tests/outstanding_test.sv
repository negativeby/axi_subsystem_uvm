`ifndef OUTSTANDING_TEST_SV
`define OUTSTANDING_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class outstanding_test extends base_test;

    `uvm_component_utils(outstanding_test)

    function new(string name = "outstanding_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_outstanding_sequence #(32, 64, 8) ot_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(), "outstanding_test 启动，等待复位释放...", UVM_LOW)
        wait(tb_top.rst_n === 1'b1);
        @(posedge tb_top.clk);

        ot_seq = axi_outstanding_sequence #(32, 64, 8)::type_id::create("ot_seq");
        ot_seq.start(env.m_agent.sqr);

        #200ns;
        `uvm_info(get_type_name(), "Outstanding 压力测试结束，准备退出仿真", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: outstanding_test

`endif // OUTSTANDING_TEST_SV

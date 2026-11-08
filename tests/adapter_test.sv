`ifndef ADAPTER_TEST_SV
`define ADAPTER_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class adapter_test extends base_test;

    `uvm_component_utils(adapter_test)

    function new(string name = "adapter_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_adapter_sequence #(32, 64, 8) adpt_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(), "adapter_test 启动，等待复位释放...", UVM_LOW)
        wait(tb_top.rst_n === 1'b1);
        @(posedge tb_top.clk);

        adpt_seq = axi_adapter_sequence #(32, 64, 8)::type_id::create("adpt_seq");
        adpt_seq.start(env.m_agent.sqr);

        #200ns;
        `uvm_info(get_type_name(), "适配桥测试执行完毕，准备退出仿真", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: adapter_test

`endif // ADAPTER_TEST_SV

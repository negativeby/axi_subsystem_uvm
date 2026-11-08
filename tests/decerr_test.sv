`ifndef DECERR_TEST_SV
`define DECERR_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class decerr_test extends base_test;

    `uvm_component_utils(decerr_test)

    function new(string name = "decerr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_decerr_sequence #(32, 64, 8) err_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(), "decerr_test 启动，等待复位释放...", UVM_LOW)
        wait(tb_top.rst_n === 1'b1);
        @(posedge tb_top.clk);

        err_seq = axi_decerr_sequence #(32, 64, 8)::type_id::create("err_seq");
        err_seq.start(env.m_agent.sqr);

        #200ns;
        `uvm_info(get_type_name(), "DECERR 异常测试结束，准备退出仿真", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: decerr_test

`endif // DECERR_TEST_SV

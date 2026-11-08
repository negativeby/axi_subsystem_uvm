`ifndef PINGPONG_TEST_SV
`define PINGPONG_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class pingpong_test extends base_test;

    `uvm_component_utils(pingpong_test)

    function new(string name = "pingpong_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_pingpong_sequence #(32, 64, 8) pp_seq;

        phase.raise_objection(this);
        `uvm_info(get_type_name(), "pingpong_test 启动，等待复位释放...", UVM_LOW)
        wait(tb_top.rst_n === 1'b1);
        @(posedge tb_top.clk);

        pp_seq = axi_pingpong_sequence #(32, 64, 8)::type_id::create("pp_seq");
        pp_seq.start(env.m_agent.sqr);

        #200ns;
        `uvm_info(get_type_name(), "乒乓测试全部完成，准备退出仿真", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: pingpong_test

`endif // PINGPONG_TEST_SV

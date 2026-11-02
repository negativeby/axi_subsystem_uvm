`ifndef RANDOM_TEST_SV
`define RANDOM_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

class random_test extends base_test;
    `uvm_component_utils(random_test)

    function new(string name = "random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        axi_random_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) rand_seq;

        super.run_phase(phase);

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "random_test 进入 run_phase，等待系统复位就绪...", UVM_LOW)
        #120; // 遵循 base_test 约定，等待 tb_top 中的 100ns 复位释放并留出余量

        // 实例化随机序列并挂载到 Agent 的 Sequencer 上
        rand_seq = axi_random_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("rand_seq");
        rand_seq.num_trans = 50; // 50 轮随机写读 (共 100 笔事务)
        rand_seq.start(env.m_agent.sqr);

        #100; // 留出 Drain Time，等待总线尾部时序与 Scoreboard 对账完成

        `uvm_info(get_type_name(), "随机测试序列全部完成，准备结束仿真", UVM_LOW)
        phase.drop_objection(this);
    endtask: run_phase

endclass: random_test

`endif // RANDOM_TEST_SV

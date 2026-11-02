`ifndef BASE_TEST_SV
`define BASE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

// 引入环境与序列
`include "axi_scoreboard.sv"
`include "axi_env.sv"
`include "axi_base_sequence.sv"

class base_test extends uvm_test;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 64;
    localparam ID_WIDTH   = 8;

    // 声明顶层环境句柄
    axi_env #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) env;

    // 工厂注册 (非参数化类，使用 uvm_component_utils)
    `uvm_component_utils(base_test)

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 实例化顶层环境
        env = axi_env #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("env", this);
    endfunction: build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        // 打印整个 UVM 验证平台的拓扑树，方便审查层次
        `uvm_info("BASE_TEST", "打印验证平台拓扑结构树:", UVM_LOW)
        uvm_top.print_topology();
    endfunction: end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        axi_base_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) seq;

        super.run_phase(phase);

        // 1. 举手表示有仿真任务进行，阻止仿真器提前退出
        phase.raise_objection(this);

        `uvm_info("BASE_TEST", "base_test 进入 run_phase，等待系统复位就绪...", UVM_LOW)
        #120; // 等待 tb_top 中的 100ns 复位释放并留出余量

        // 2. 实例化并启动冒烟序列，挂载到 Agent 的 Sequencer 上
        seq = axi_base_sequence #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("seq");
        seq.start(env.m_agent.sqr);

        // 3. 留出 100ns 的 Drain Time，确保所有总线尾部时序与 Scoreboard 对账完成
        #100;

        `uvm_info("BASE_TEST", "冒烟测试执行完毕，准备结束仿真", UVM_LOW)

        // 4. 放下反对票，允许 UVM 进入 check_phase 与 final_phase 结束仿真
        phase.drop_objection(this);
    endtask: run_phase

endclass: base_test

`endif // BASE_TEST_SV

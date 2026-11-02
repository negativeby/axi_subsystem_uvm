`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_agent #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_agent;

    // 内部三大子组件句柄
    axi_driver    #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) drv;
    axi_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) sqr;
    axi_monitor   #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) mon;

    // 暴露给外部 Env/Scoreboard 的 TLM 分析广播端口
    uvm_analysis_port #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)) item_collected_port;

    `uvm_component_param_utils(axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 1. Monitor 属于被动采样器，无论 Active 还是 Passive 模式都必须实例化
        mon = axi_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("mon", this);

        // 2. 检查当前 Agent 的工作模式 (默认为 UVM_ACTIVE)
        if (get_is_active() == UVM_ACTIVE) begin
            drv = axi_driver    #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("drv", this);
            sqr = axi_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("sqr", this);
        end

        // 3. 实例化对外的广播端口
        item_collected_port = new("item_collected_port", this);
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // 1. 将 Monitor 的广播端口与 Agent 的对外广播端口连接 (对接同类型 TLM 端口)
        mon.item_collected_port.connect(this.item_collected_port);

        // 2. 如果处于 Active 模式，必须将 Driver 的取数据端口与 Sequencer 的供数据端口相连
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction: connect_phase

endclass: axi_agent

`endif // AXI_AGENT_SV

`ifndef AXI_ENV_SV
`define AXI_ENV_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

`include "axi_scoreboard.sv"
`include "axi_coverage.sv"

// ==============================================================
// 就地声明 AXI 虚拟音序器 (Virtual Sequencer)
// ==============================================================
class axi_virtual_sequencer #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8
) extends uvm_sequencer;

    `uvm_component_param_utils(axi_virtual_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    axi_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m0_sqr;
    axi_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m1_sqr;

    function new(string name = "axi_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

endclass: axi_virtual_sequencer


// ==============================================================
// AXI 顶层验证环境 (axi_env)
// ==============================================================
class axi_env #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8
) extends uvm_env;

    // 两路对等的全功能 Active VIP Agent
    axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m0_agent;
    axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m1_agent;

    // 向下兼容别名句柄 (直接指向 m0_agent，彻底消灭 base_test 的编译错误)
    axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_agent;

    // 虚拟音序器
    axi_virtual_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) v_sqr;

    // 全局裁判与覆盖率收集器
    axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_scb;
    axi_coverage   #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_cov;

    `uvm_component_param_utils(axi_env #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 实例化两路主动 Master VIP
        m0_agent = axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m0_agent", this);
        m1_agent = axi_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m1_agent", this);

        // 句柄别名绑定: 兼容任何访问 env.m_agent 的旧用例
        m_agent  = m0_agent;

        v_sqr    = axi_virtual_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("v_sqr", this);
        m_scb    = axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m_scb", this);
        m_cov    = axi_coverage   #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m_cov", this);
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // 1. 物理音序器句柄注入 Virtual Sequencer
        v_sqr.m0_sqr = m0_agent.sqr;
        v_sqr.m1_sqr = m1_agent.sqr;

        // 2. 双路 Monitor 的采样流分别接入 Scoreboard 的 M0 与 M1 专属通道
        m0_agent.item_collected_port.connect(m_scb.item_collected_export_m0);
        m1_agent.item_collected_port.connect(m_scb.item_collected_export_m1);

        // 3. 双路 Monitor 接入覆盖率收集器 (解决 M1 漏采问题)
        m0_agent.item_collected_port.connect(m_cov.analysis_export_m0);
        m1_agent.item_collected_port.connect(m_cov.analysis_export_m1);
    endfunction: connect_phase

endclass: axi_env

`endif // AXI_ENV_SV

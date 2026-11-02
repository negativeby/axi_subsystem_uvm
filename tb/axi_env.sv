`ifndef AXI_ENV_SV
`define AXI_ENV_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_vip_pkg::*;

`include "axi_scoreboard.sv"
`include "axi_coverage.sv"

class axi_env #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_env;

    axi_agent      #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_agent;
    axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_scb;
    axi_coverage   #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) m_cov;

    `uvm_component_param_utils(axi_env #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_agent = axi_agent    #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m_agent", this);
        m_scb   = axi_scoreboard #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m_scb", this);
        m_cov   = axi_coverage   #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH)::type_id::create("m_cov", this);
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // 1. 广播流分支 1: 送给 Scoreboard 裁判对账
        m_agent.item_collected_port.connect(m_scb.item_collected_export);
        // 2. 广播流分支 2: 送给 Coverage 收集器统计度量
        m_agent.item_collected_port.connect(m_cov.analysis_export);
    endfunction: connect_phase

endclass: axi_env

`endif // AXI_ENV_SV

`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_sequencer #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 8
) extends uvm_sequencer #(axi_transfer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH));

    `uvm_component_param_utils(axi_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH))

    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

endclass: axi_sequencer

`endif // AXI_SEQUENCER_SV

`ifndef AXI_VIP_PKG_SV
`define AXI_VIP_PKG_SV

`include "uvm_macros.svh"

package axi_vip_pkg;
    import uvm_pkg::*;

    // 按照继承与依赖依赖顺序包含 VIP 组件
    `include "axi_transfer.sv"
    `include "axi_driver.sv"
    `include "axi_sequencer.sv"
    `include "axi_monitor.sv"
    `include "axi_agent.sv"

endpackage: axi_vip_pkg

`endif // AXI_VIP_PKG_SV

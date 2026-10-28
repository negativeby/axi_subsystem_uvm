`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// 声明一个最基础的 UVM 空测试用例
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("BASE_TEST", "========================================", UVM_LOW)
        `uvm_info("BASE_TEST", "VCS + UVM 仿真与环境配置成功打通！", UVM_LOW)
        `uvm_info("BASE_TEST", "========================================", UVM_LOW)
        #100ns;
        phase.drop_objection(this);
    endtask
endclass

module tb_top;
    // 时钟与复位生成
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz 时钟
    end

    initial begin
        rst_n = 0;
        #20ns rst_n = 1;
    end

    // 录制 Verdi 专用的 FSDB 波形文件
    initial begin
        $fsdbDumpfile("tb_top.fsdb");
        $fsdbDumpvars(0, tb_top);
    end

    // 启动 UVM
    initial begin
        run_test();
    end
endmodule

`timescale 1ns/1ps

interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 8,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic clk,
    input logic rst_n
);

    // ==========================================
    // 1. 写地址通道 (AW Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    awid;     // 写事务 ID
    logic [ADDR_WIDTH-1:0]  awaddr;   // 起始写地址
    logic [7:0]             awlen;    // 突发拍数 - 1
    logic [2:0]             awsize;   // 每拍字节数 (3'b011 代表 8 字节 = 64位)
    logic [1:0]             awburst;  // 突发类型 (01: INCR 地址递增)
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic                   awvalid;  // 主机发起有效写地址
    logic                   awready;  // 从机准备好接收写地址

    // ==========================================
    // 2. 写数据通道 (W Channel)
    // ==========================================
    logic [DATA_WIDTH-1:0]  wdata;    // 64 位写数据
    logic [STRB_WIDTH-1:0]  wstrb;    // 字节使能 (控制 8 个字节中哪几个有效)
    logic                   wlast;    // 突发最后一拍标志
    logic                   wvalid;   // 主机发出有效数据
    logic                   wready;   // 从机准备好收数据

    // ==========================================
    // 3. 写响应通道 (B Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    bid;      // 返回的写事务 ID
    logic [1:0]             bresp;    // 写状态回执 (00: OKAY, 非0: 出错)
    logic                   bvalid;   // 从机发出写回执
    logic                   bready;   // 主机准备好接收回执
    // ==========================================
    // 4. 读地址通道 (AR Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    arid;     // 读事务 ID
    logic [ADDR_WIDTH-1:0]  araddr;   // 起始读地址
    logic [7:0]             arlen;    // 突发读拍数 - 1
    logic [2:0]             arsize;   // 每拍字节数
    logic [1:0]             arburst;  // 突发类型 (01: INCR)
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic                   arvalid;  // 主机发起有效读请求
    logic                   arready;  // 从机准备好接收读请求

    // ==========================================
    // 5. 读数据通道 (R Channel)
    // ==========================================
    logic [ID_WIDTH-1:0]    rid;      // 返回的读事务 ID
    logic [DATA_WIDTH-1:0]  rdata;    // 从机返回的 64 位读数据
    logic [1:0]             rresp;    // 每拍读状态回执
    logic                   rlast;    // 突发读最后一拍标志
    logic                   rvalid;   // 从机送出有效读数据
    logic                   rready;   // 主机准备好接收读数据
    
    // ==========================================
    // 6. 时钟块 (Clocking Block) —— 消除竞争冒险
    // ==========================================
    // Master Driver 用的时钟块：在时钟沿前采样输入，在时钟沿后驱动输出
    clocking mst_drv_cb @(posedge clk);
        default input #1ps output #100ps;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    // Monitor 用的时钟块：全都是纯采样 (input)
    clocking mon_cb @(posedge clk);
        default input #1ps;
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    // 接口方向端口定义
    modport mst_drv_mp (clocking mst_drv_cb, input clk, input rst_n);
    modport mon_mp     (clocking mon_cb,     input clk, input rst_n);

endinterface: axi_if

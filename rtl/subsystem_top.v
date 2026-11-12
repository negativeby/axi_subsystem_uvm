`timescale 1ns/1ps

module subsystem_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter STRB_WIDTH = DATA_WIDTH / 8,
    parameter ID_WIDTH   = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // ==============================================================
    // Master 0 AXI4 接口 (s0_axi_*)
    // ==============================================================
    input  wire [ID_WIDTH-1:0]    s0_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s0_axi_awaddr,
    input  wire [7:0]             s0_axi_awlen,
    input  wire [2:0]             s0_axi_awsize,
    input  wire [1:0]             s0_axi_awburst,
    input  wire                   s0_axi_awlock,
    input  wire [3:0]             s0_axi_awcache,
    input  wire [2:0]             s0_axi_awprot,
    input  wire                   s0_axi_awvalid,
    output wire                   s0_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s0_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s0_axi_wstrb,
    input  wire                   s0_axi_wlast,
    input  wire                   s0_axi_wvalid,
    output wire                   s0_axi_wready,

    output wire [ID_WIDTH-1:0]    s0_axi_bid,
    output wire [1:0]             s0_axi_bresp,
    output wire                   s0_axi_bvalid,
    input  wire                   s0_axi_bready,

    input  wire [ID_WIDTH-1:0]    s0_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s0_axi_araddr,
    input  wire [7:0]             s0_axi_arlen,
    input  wire [2:0]             s0_axi_arsize,
    input  wire [1:0]             s0_axi_arburst,
    input  wire                   s0_axi_arlock,
    input  wire [3:0]             s0_axi_arcache,
    input  wire [2:0]             s0_axi_arprot,
    input  wire                   s0_axi_arvalid,
    output wire                   s0_axi_arready,

    output wire [ID_WIDTH-1:0]    s0_axi_rid,
    output wire [DATA_WIDTH-1:0]  s0_axi_rdata,
    output wire [1:0]             s0_axi_rresp,
    output wire                   s0_axi_rlast,
    output wire                   s0_axi_rvalid,
    input  wire                   s0_axi_rready,

    // ==============================================================
    // Master 1 AXI4 接口 (s1_axi_*)
    // ==============================================================
    input  wire [ID_WIDTH-1:0]    s1_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s1_axi_awaddr,
    input  wire [7:0]             s1_axi_awlen,
    input  wire [2:0]             s1_axi_awsize,
    input  wire [1:0]             s1_axi_awburst,
    input  wire                   s1_axi_awlock,
    input  wire [3:0]             s1_axi_awcache,
    input  wire [2:0]             s1_axi_awprot,
    input  wire                   s1_axi_awvalid,
    output wire                   s1_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s1_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s1_axi_wstrb,
    input  wire                   s1_axi_wlast,
    input  wire                   s1_axi_wvalid,
    output wire                   s1_axi_wready,

    output wire [ID_WIDTH-1:0]    s1_axi_bid,
    output wire [1:0]             s1_axi_bresp,
    output wire                   s1_axi_bvalid,
    input  wire                   s1_axi_bready,

    input  wire [ID_WIDTH-1:0]    s1_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s1_axi_araddr,
    input  wire [7:0]             s1_axi_arlen,
    input  wire [2:0]             s1_axi_arsize,
    input  wire [1:0]             s1_axi_arburst,
    input  wire                   s1_axi_arlock,
    input  wire [3:0]             s1_axi_arcache,
    input  wire [2:0]             s1_axi_arprot,
    input  wire                   s1_axi_arvalid,
    output wire                   s1_axi_arready,

    output wire [ID_WIDTH-1:0]    s1_axi_rid,
    output wire [DATA_WIDTH-1:0]  s1_axi_rdata,
    output wire [1:0]             s1_axi_rresp,
    output wire                   s1_axi_rlast,
    output wire                   s1_axi_rvalid,
    input  wire                   s1_axi_rready
);

    wire rst = ~rst_n;

    localparam S_COUNT    = 2;
    localparam M_COUNT    = 2;
    localparam M_ID_WIDTH = ID_WIDTH + 1;

    // Crossbar 输出给 Slave 0 (axi_ram) 的信号线
    wire [M_ID_WIDTH-1:0]   m0_axi_awid,   m0_axi_bid,   m0_axi_arid,   m0_axi_rid;
    wire [ADDR_WIDTH-1:0]   m0_axi_awaddr, m0_axi_araddr;
    wire [7:0]              m0_axi_awlen,  m0_axi_arlen;
    wire [2:0]              m0_axi_awsize, m0_axi_arsize, m0_axi_awprot, m0_axi_arprot;
    wire [1:0]              m0_axi_awburst,m0_axi_arburst,m0_axi_bresp,  m0_axi_rresp;
    wire [3:0]              m0_axi_awcache,m0_axi_arcache;
    wire [DATA_WIDTH-1:0]   m0_axi_wdata,  m0_axi_rdata;
    wire [STRB_WIDTH-1:0]   m0_axi_wstrb;
    wire                    m0_axi_awlock, m0_axi_awvalid, m0_axi_awready;
    wire                    m0_axi_wlast,  m0_axi_wvalid,  m0_axi_wready;
    wire                    m0_axi_bvalid, m0_axi_bready;
    wire                    m0_axi_arlock, m0_axi_arvalid, m0_axi_arready;
    wire                    m0_axi_rlast,  m0_axi_rvalid,  m0_axi_rready;

    // Crossbar 输出给 Slave 1 (axi_axil_adapter) 的信号线
    wire [M_ID_WIDTH-1:0]   m1_axi_awid,   m1_axi_bid,   m1_axi_arid,   m1_axi_rid;
    wire [ADDR_WIDTH-1:0]   m1_axi_awaddr, m1_axi_araddr;
    wire [7:0]              m1_axi_awlen,  m1_axi_arlen;
    wire [2:0]              m1_axi_awsize, m1_axi_arsize, m1_axi_awprot, m1_axi_arprot;
    wire [1:0]              m1_axi_awburst,m1_axi_arburst,m1_axi_bresp,  m1_axi_rresp;
    wire [3:0]              m1_axi_awcache,m1_axi_arcache;
    wire [DATA_WIDTH-1:0]   m1_axi_wdata,  m1_axi_rdata;
    wire [STRB_WIDTH-1:0]   m1_axi_wstrb;
    wire                    m1_axi_awlock, m1_axi_awvalid, m1_axi_awready;
    wire                    m1_axi_wlast,  m1_axi_wvalid,  m1_axi_wready;
    wire                    m1_axi_bvalid, m1_axi_bready;
    wire                    m1_axi_arlock, m1_axi_arvalid, m1_axi_arready;
    wire                    m1_axi_rlast,  m1_axi_rvalid,  m1_axi_rready;

    // Adapter 转出的 32 位 AXI-Lite 信号线
    wire [ADDR_WIDTH-1:0]  axil_awaddr, axil_araddr;
    wire [2:0]             axil_awprot, axil_arprot;
    wire [31:0]            axil_wdata,  axil_rdata;
    wire [3:0]             axil_wstrb;
    wire [1:0]             axil_bresp,  axil_rresp;
    wire                   axil_awvalid, axil_awready;
    wire                   axil_wvalid,  axil_wready;
    wire                   axil_bvalid,  axil_bready;
    wire                   axil_arvalid, axil_arready;
    wire                   axil_rvalid,  axil_rready;

    // ==============================================================
    // 2x2 AXI Crossbar 互联矩阵
    // ==============================================================
    axi_crossbar #(
        .S_COUNT(S_COUNT),
        .M_COUNT(M_COUNT),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .S_ID_WIDTH(ID_WIDTH),
        .M_ADDR_WIDTH({32'd12, 32'd15}),
        .M_BASE_ADDR({32'h0001_0000, 32'h0000_0000}),
        .M_CONNECT_READ(4'b1111),
        .M_CONNECT_WRITE(4'b1111),
        .S_W_REG_TYPE({S_COUNT{2'd2}})
    ) u_crossbar (
        .clk(clk),
        .rst(rst),

        // S_AXI 接口 (标准 AXI4: 使用 s_axi_*)
        .s_axi_awid({s1_axi_awid, s0_axi_awid}),
        .s_axi_awaddr({s1_axi_awaddr, s0_axi_awaddr}),
        .s_axi_awlen({s1_axi_awlen, s0_axi_awlen}),
        .s_axi_awsize({s1_axi_awsize, s0_axi_awsize}),
        .s_axi_awburst({s1_axi_awburst, s0_axi_awburst}),
        .s_axi_awlock({s1_axi_awlock, s0_axi_awlock}),
        .s_axi_awcache({s1_axi_awcache, s0_axi_awcache}),
        .s_axi_awprot({s1_axi_awprot, s0_axi_awprot}),
        .s_axi_awuser({2{1'b0}}),
        .s_axi_awvalid({s1_axi_awvalid, s0_axi_awvalid}),
        .s_axi_awready({s1_axi_awready, s0_axi_awready}),

        .s_axi_wdata({s1_axi_wdata, s0_axi_wdata}),
        .s_axi_wstrb({s1_axi_wstrb, s0_axi_wstrb}),
        .s_axi_wlast({s1_axi_wlast, s0_axi_wlast}),
        .s_axi_wuser({2{1'b0}}),
        .s_axi_wvalid({s1_axi_wvalid, s0_axi_wvalid}),
        .s_axi_wready({s1_axi_wready, s0_axi_wready}),

        .s_axi_bid({s1_axi_bid, s0_axi_bid}),
        .s_axi_bresp({s1_axi_bresp, s0_axi_bresp}),
        .s_axi_buser(),
        .s_axi_bvalid({s1_axi_bvalid, s0_axi_bvalid}),
        .s_axi_bready({s1_axi_bready, s0_axi_bready}),

        .s_axi_arid({s1_axi_arid, s0_axi_arid}),
        .s_axi_araddr({s1_axi_araddr, s0_axi_araddr}),
        .s_axi_arlen({s1_axi_arlen, s0_axi_arlen}),
        .s_axi_arsize({s1_axi_arsize, s0_axi_arsize}),
        .s_axi_arburst({s1_axi_arburst, s0_axi_arburst}),
        .s_axi_arlock({s1_axi_arlock, s0_axi_arlock}),
        .s_axi_arcache({s1_axi_arcache, s0_axi_arcache}),
        .s_axi_arprot({s1_axi_arprot, s0_axi_arprot}),
        .s_axi_aruser({2{1'b0}}),
        .s_axi_arvalid({s1_axi_arvalid, s0_axi_arvalid}),
        .s_axi_arready({s1_axi_arready, s0_axi_arready}),

        .s_axi_rid({s1_axi_rid, s0_axi_rid}),
        .s_axi_rdata({s1_axi_rdata, s0_axi_rdata}),
        .s_axi_rresp({s1_axi_rresp, s0_axi_rresp}),
        .s_axi_rlast({s1_axi_rlast, s0_axi_rlast}),
        .s_axi_ruser(),
        .s_axi_rvalid({s1_axi_rvalid, s0_axi_rvalid}),
        .s_axi_rready({s1_axi_rready, s0_axi_rready}),

        // M_AXI 接口
        .m_axi_awid({m1_axi_awid, m0_axi_awid}),
        .m_axi_awaddr({m1_axi_awaddr, m0_axi_awaddr}),
        .m_axi_awlen({m1_axi_awlen, m0_axi_awlen}),
        .m_axi_awsize({m1_axi_awsize, m0_axi_awsize}),
        .m_axi_awburst({m1_axi_awburst, m0_axi_awburst}),
        .m_axi_awlock({m1_axi_awlock, m0_axi_awlock}),
        .m_axi_awcache({m1_axi_awcache, m0_axi_awcache}),
        .m_axi_awprot({m1_axi_awprot, m0_axi_awprot}),
        .m_axi_awuser(),
        .m_axi_awvalid({m1_axi_awvalid, m0_axi_awvalid}),
        .m_axi_awready({m1_axi_awready, m0_axi_awready}),

        .m_axi_wdata({m1_axi_wdata, m0_axi_wdata}),
        .m_axi_wstrb({m1_axi_wstrb, m0_axi_wstrb}),
        .m_axi_wlast({m1_axi_wlast, m0_axi_wlast}),
        .m_axi_wuser(),
        .m_axi_wvalid({m1_axi_wvalid, m0_axi_wvalid}),
        .m_axi_wready({m1_axi_wready, m0_axi_wready}),

        .m_axi_bid({m1_axi_bid, m0_axi_bid}),
        .m_axi_bresp({m1_axi_bresp, m0_axi_bresp}),
        .m_axi_buser({2{1'b0}}),
        .m_axi_bvalid({m1_axi_bvalid, m0_axi_bvalid}),
        .m_axi_bready({m1_axi_bready, m0_axi_bready}),

        .m_axi_arid({m1_axi_arid, m0_axi_arid}),
        .m_axi_araddr({m1_axi_araddr, m0_axi_araddr}),
        .m_axi_arlen({m1_axi_arlen, m0_axi_arlen}),
        .m_axi_arsize({m1_axi_arsize, m0_axi_arsize}),
        .m_axi_arburst({m1_axi_arburst, m0_axi_arburst}),
        .m_axi_arlock({m1_axi_arlock, m0_axi_arlock}),
        .m_axi_arcache({m1_axi_arcache, m0_axi_arcache}),
        .m_axi_arprot({m1_axi_arprot, m0_axi_arprot}),
        .m_axi_aruser(),
        .m_axi_arvalid({m1_axi_arvalid, m0_axi_arvalid}),
        .m_axi_arready({m1_axi_arready, m0_axi_arready}),

        .m_axi_rid({m1_axi_rid, m0_axi_rid}),
        .m_axi_rdata({m1_axi_rdata, m0_axi_rdata}),
        .m_axi_rresp({m1_axi_rresp, m0_axi_rresp}),
        .m_axi_rlast({m1_axi_rlast, m0_axi_rlast}),
        .m_axi_ruser({2{1'b0}}),
        .m_axi_rvalid({m1_axi_rvalid, m0_axi_rvalid}),
        .m_axi_rready({m1_axi_rready, m0_axi_rready})
    );

    // Slave 0: 高速 AXI4 RAM (标准 AXI4: 使用 s_axi_*)
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(15),
        .ID_WIDTH(M_ID_WIDTH)
    ) u_axi_ram (
        .clk(clk),
        .rst(rst),
        .s_axi_awid(m0_axi_awid),
        .s_axi_awaddr(m0_axi_awaddr[14:0]),
        .s_axi_awlen(m0_axi_awlen),
        .s_axi_awsize(m0_axi_awsize),
        .s_axi_awburst(m0_axi_awburst),
        .s_axi_awlock(m0_axi_awlock),
        .s_axi_awcache(m0_axi_awcache),
        .s_axi_awprot(m0_axi_awprot),
        .s_axi_awvalid(m0_axi_awvalid),
        .s_axi_awready(m0_axi_awready),
        .s_axi_wdata(m0_axi_wdata),
        .s_axi_wstrb(m0_axi_wstrb),
        .s_axi_wlast(m0_axi_wlast),
        .s_axi_wvalid(m0_axi_wvalid),
        .s_axi_wready(m0_axi_wready),
        .s_axi_bid(m0_axi_bid),
        .s_axi_bresp(m0_axi_bresp),
        .s_axi_bvalid(m0_axi_bvalid),
        .s_axi_bready(m0_axi_bready),
        .s_axi_arid(m0_axi_arid),
        .s_axi_araddr(m0_axi_araddr[14:0]),
        .s_axi_arlen(m0_axi_arlen),
        .s_axi_arsize(m0_axi_arsize),
        .s_axi_arburst(m0_axi_arburst),
        .s_axi_arlock(m0_axi_arlock),
        .s_axi_arcache(m0_axi_arcache),
        .s_axi_arprot(m0_axi_arprot),
        .s_axi_arvalid(m0_axi_arvalid),
        .s_axi_arready(m0_axi_arready),
        .s_axi_rid(m0_axi_rid),
        .s_axi_rdata(m0_axi_rdata),
        .s_axi_rresp(m0_axi_rresp),
        .s_axi_rlast(m0_axi_rlast),
        .s_axi_rvalid(m0_axi_rvalid),
        .s_axi_rready(m0_axi_rready)
    );

    // Slave 1: 跨协议桥与低速 AXI-Lite RAM
    axi_axil_adapter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ID_WIDTH(M_ID_WIDTH),
        .AXIL_DATA_WIDTH(32),
        .CONVERT_BURST(1)
    ) u_bridge (
        .clk(clk),
        .rst(rst),
        // 从机端为 AXI4 (使用 s_axi_*)
        .s_axi_awid(m1_axi_awid),
        .s_axi_awaddr(m1_axi_awaddr),
        .s_axi_awlen(m1_axi_awlen),
        .s_axi_awsize(m1_axi_awsize),
        .s_axi_awburst(m1_axi_awburst),
        .s_axi_awlock(m1_axi_awlock),
        .s_axi_awcache(m1_axi_awcache),
        .s_axi_awprot(m1_axi_awprot),
        .s_axi_awvalid(m1_axi_awvalid),
        .s_axi_awready(m1_axi_awready),
        .s_axi_wdata(m1_axi_wdata),
        .s_axi_wstrb(m1_axi_wstrb),
        .s_axi_wlast(m1_axi_wlast),
        .s_axi_wvalid(m1_axi_wvalid),
        .s_axi_wready(m1_axi_wready),
        .s_axi_bid(m1_axi_bid),
        .s_axi_bresp(m1_axi_bresp),
        .s_axi_bvalid(m1_axi_bvalid),
        .s_axi_bready(m1_axi_bready),
        .s_axi_arid(m1_axi_arid),
        .s_axi_araddr(m1_axi_araddr),
        .s_axi_arlen(m1_axi_arlen),
        .s_axi_arsize(m1_axi_arsize),
        .s_axi_arburst(m1_axi_arburst),
        .s_axi_arlock(m1_axi_arlock),
        .s_axi_arcache(m1_axi_arcache),
        .s_axi_arprot(m1_axi_arprot),
        .s_axi_arvalid(m1_axi_arvalid),
        .s_axi_arready(m1_axi_arready),
        .s_axi_rid(m1_axi_rid),
        .s_axi_rdata(m1_axi_rdata),
        .s_axi_rresp(m1_axi_rresp),
        .s_axi_rlast(m1_axi_rlast),
        .s_axi_rvalid(m1_axi_rvalid),
        .s_axi_rready(m1_axi_rready),

        // 主机端为 AXI-Lite (使用 m_axil_*)
        .m_axil_awaddr(axil_awaddr),
        .m_axil_awprot(axil_awprot),
        .m_axil_awvalid(axil_awvalid),
        .m_axil_awready(axil_awready),
        .m_axil_wdata(axil_wdata),
        .m_axil_wstrb(axil_wstrb),
        .m_axil_wvalid(axil_wvalid),
        .m_axil_wready(axil_wready),
        .m_axil_bresp(axil_bresp),
        .m_axil_bvalid(axil_bvalid),
        .m_axil_bready(axil_bready),
        .m_axil_araddr(axil_araddr),
        .m_axil_arprot(axil_arprot),
        .m_axil_arvalid(axil_arvalid),
        .m_axil_arready(axil_arready),
        .m_axil_rdata(axil_rdata),
        .m_axil_rresp(axil_rresp),
        .m_axil_rvalid(axil_rvalid),
        .m_axil_rready(axil_rready)
    );

    // axil_ram (纯 AXI-Lite 从机: 统一为 s_axil_*)
    axil_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12)
    ) u_axil_ram (
        .clk(clk),
        .rst(rst),
        .s_axil_awaddr(axil_awaddr[11:0]),
        .s_axil_awprot(axil_awprot),
        .s_axil_awvalid(axil_awvalid),
        .s_axil_awready(axil_awready),
        .s_axil_wdata(axil_wdata),
        .s_axil_wstrb(axil_wstrb),
        .s_axil_wvalid(axil_wvalid),
        .s_axil_wready(axil_wready),
        .s_axil_bresp(axil_bresp),
        .s_axil_bvalid(axil_bvalid),
        .s_axil_bready(axil_bready),
        .s_axil_araddr(axil_araddr[11:0]),
        .s_axil_arprot(axil_arprot),
        .s_axil_arvalid(axil_arvalid),
        .s_axil_arready(axil_arready),
        .s_axil_rdata(axil_rdata),
        .s_axil_rresp(axil_rresp),
        .s_axil_rvalid(axil_rvalid),
        .s_axil_rready(axil_rready)
    );

endmodule: subsystem_top

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
    // 外部 Master 0 接口 (供 UVM TB 的 axi_if 接入，模拟 CPU 访问)
    // ==============================================================
    // 写地址通道 (AW)
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    // 写数据通道 (W)
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    // 写响应通道 (B)
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    // 读地址通道 (AR)
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    // 读数据通道 (R)
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // ==============================================================
    // DMA 控制描述符流接口 (供 TB 下发搬运指令)
    // ==============================================================
    input  wire [ADDR_WIDTH-1:0]  dma_read_desc_addr,
    input  wire [15:0]            dma_read_desc_len,
    input  wire [7:0]             dma_read_desc_tag,
    input  wire                   dma_read_desc_valid,
    output wire                   dma_read_desc_ready,

    input  wire [ADDR_WIDTH-1:0]  dma_write_desc_addr,
    input  wire [15:0]            dma_write_desc_len,
    input  wire [7:0]             dma_write_desc_tag,
    input  wire                   dma_write_desc_valid,
    output wire                   dma_write_desc_ready
);
// ==============================================================
    // 内部控制与复位信号
    // ==============================================================
    // Alex 的 RTL 内部使用高电平复位 (rst)，外部接口为低电平复位 (rst_n)
    wire rst = ~rst_n;

    // Crossbar 主从数量与位宽参数
    localparam S_COUNT    = 2;
    localparam M_COUNT    = 2;
    localparam M_ID_WIDTH = ID_WIDTH + 1; // Crossbar 会向 ID 尾部追加 1 位主设备标识

    // ==============================================================
    // 1. DMA 主机端发出的 AXI4 信号线 (作为 Crossbar 的 Master 1)
    // ==============================================================
    wire [ID_WIDTH-1:0]    dma_axi_awid;
    wire [ADDR_WIDTH-1:0]  dma_axi_awaddr;
    wire [7:0]             dma_axi_awlen;
    wire [2:0]             dma_axi_awsize;
    wire [1:0]             dma_axi_awburst;
    wire                   dma_axi_awlock;
    wire [3:0]             dma_axi_awcache;
    wire [2:0]             dma_axi_awprot;
    wire                   dma_axi_awvalid;
    wire                   dma_axi_awready;

    wire [DATA_WIDTH-1:0]  dma_axi_wdata;
    wire [STRB_WIDTH-1:0]  dma_axi_wstrb;
    wire                   dma_axi_wlast;
    wire                   dma_axi_wvalid;
    wire                   dma_axi_wready;

    wire [ID_WIDTH-1:0]    dma_axi_bid;
    wire [1:0]             dma_axi_bresp;
    wire                   dma_axi_bvalid;
    wire                   dma_axi_bready;

    wire [ID_WIDTH-1:0]    dma_axi_arid;
    wire [ADDR_WIDTH-1:0]  dma_axi_araddr;
    wire [7:0]             dma_axi_arlen;
    wire [2:0]             dma_axi_arsize;
    wire [1:0]             dma_axi_arburst;
    wire                   dma_axi_arlock;
    wire [3:0]             dma_axi_arcache;
    wire [2:0]             dma_axi_arprot;
    wire                   dma_axi_arvalid;
    wire                   dma_axi_arready;

    wire [ID_WIDTH-1:0]    dma_axi_rid;
    wire [DATA_WIDTH-1:0]  dma_axi_rdata;
    wire [1:0]             dma_axi_rresp;
    wire                   dma_axi_rlast;
    wire                   dma_axi_rvalid;
    wire                   dma_axi_rready;

    // DMA 读写引擎之间的内部 AXI-Stream 数据流直连 (构建内存自搬移回路)
    wire [DATA_WIDTH-1:0]  dma_axis_data;
    wire [STRB_WIDTH-1:0]  dma_axis_keep;
    wire                   dma_axis_valid;
    wire                   dma_axis_ready;
    wire                   dma_axis_last;

    // ==============================================================
    // 2. Crossbar 输出给 Slave 0 (axi_ram) 的 64 位信号线
    // ==============================================================
    wire [M_ID_WIDTH-1:0]   m0_axi_awid;
    wire [ADDR_WIDTH-1:0]   m0_axi_awaddr;
    wire [7:0]              m0_axi_awlen;
    wire [2:0]              m0_axi_awsize;
    wire [1:0]              m0_axi_awburst;
    wire                    m0_axi_awlock;
    wire [3:0]              m0_axi_awcache;
    wire [2:0]              m0_axi_awprot;
    wire                    m0_axi_awvalid;
    wire                    m0_axi_awready;

    wire [DATA_WIDTH-1:0]   m0_axi_wdata;
    wire [STRB_WIDTH-1:0]   m0_axi_wstrb;
    wire                    m0_axi_wlast;
    wire                    m0_axi_wvalid;
    wire                    m0_axi_wready;

    wire [M_ID_WIDTH-1:0]   m0_axi_bid;
    wire [1:0]              m0_axi_bresp;
    wire                    m0_axi_bvalid;
    wire                    m0_axi_bready;

    wire [M_ID_WIDTH-1:0]   m0_axi_arid;
    wire [ADDR_WIDTH-1:0]   m0_axi_araddr;
    wire [7:0]              m0_axi_arlen;
    wire [2:0]              m0_axi_arsize;
    wire [1:0]              m0_axi_arburst;
    wire                    m0_axi_arlock;
    wire [3:0]              m0_axi_arcache;
    wire [2:0]              m0_axi_arprot;
    wire                    m0_axi_arvalid;
    wire                    m0_axi_arready;

    wire [M_ID_WIDTH-1:0]   m0_axi_rid;
    wire [DATA_WIDTH-1:0]   m0_axi_rdata;
    wire [1:0]              m0_axi_rresp;
    wire                    m0_axi_rlast;
    wire                    m0_axi_rvalid;
    wire                    m0_axi_rready;

    // ==============================================================
    // 3. Crossbar 输出给 Slave 1 (axi_axil_adapter) 的 64 位信号线
    // ==============================================================
    wire [M_ID_WIDTH-1:0]   m1_axi_awid;
    wire [ADDR_WIDTH-1:0]   m1_axi_awaddr;
    wire [7:0]              m1_axi_awlen;
    wire [2:0]              m1_axi_awsize;
    wire [1:0]              m1_axi_awburst;
    wire                    m1_axi_awlock;
    wire [3:0]              m1_axi_awcache;
    wire [2:0]              m1_axi_awprot;
    wire                    m1_axi_awvalid;
    wire                    m1_axi_awready;

    wire [DATA_WIDTH-1:0]   m1_axi_wdata;
    wire [STRB_WIDTH-1:0]   m1_axi_wstrb;
    wire                    m1_axi_wlast;
    wire                    m1_axi_wvalid;
    wire                    m1_axi_wready;

    wire [M_ID_WIDTH-1:0]   m1_axi_bid;
    wire [1:0]              m1_axi_bresp;
    wire                    m1_axi_bvalid;
    wire                    m1_axi_bready;

    wire [M_ID_WIDTH-1:0]   m1_axi_arid;
    wire [ADDR_WIDTH-1:0]   m1_axi_araddr;
    wire [7:0]              m1_axi_arlen;
    wire [2:0]              m1_axi_arsize;
    wire [1:0]              m1_axi_arburst;
    wire                    m1_axi_arlock;
    wire [3:0]              m1_axi_arcache;
    wire [2:0]              m1_axi_arprot;
    wire                    m1_axi_arvalid;
    wire                    m1_axi_arready;

    wire [M_ID_WIDTH-1:0]   m1_axi_rid;
    wire [DATA_WIDTH-1:0]   m1_axi_rdata;
    wire [1:0]              m1_axi_rresp;
    wire                    m1_axi_rlast;
    wire                    m1_axi_rvalid;
    wire                    m1_axi_rready;

    // ==============================================================
    // 4. Adapter 转换出的 32 位 AXI-Lite 信号线 (连接 axil_ram)
    // ==============================================================
    wire [ADDR_WIDTH-1:0]  axil_awaddr;
    wire [2:0]             axil_awprot;
    wire                   axil_awvalid;
    wire                   axil_awready;
    wire [31:0]            axil_wdata;
    wire [3:0]             axil_wstrb;
    wire                   axil_wvalid;
    wire                   axil_wready;
    wire [1:0]             axil_bresp;
    wire                   axil_bvalid;
    wire                   axil_bready;
    wire [ADDR_WIDTH-1:0]  axil_araddr;
    wire [2:0]             axil_arprot;
    wire                   axil_arvalid;
    wire                   axil_arready;
    wire [31:0]            axil_rdata;
    wire [1:0]             axil_rresp;
    wire                   axil_rvalid;
    wire                   axil_rready;
    // ==============================================================
    // 模块 1: 片上 AXI DMA 引擎 (Master 1)
    // ==============================================================
    axi_dma #(
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ADDR_WIDTH(ADDR_WIDTH),
        .AXI_ID_WIDTH(ID_WIDTH),
        .AXIS_DATA_WIDTH(DATA_WIDTH)
    ) u_axi_dma (
        .clk(clk),
        .rst(rst),

        // 读描述符通道
        .s_axis_read_desc_addr(dma_read_desc_addr),
        .s_axis_read_desc_len({4'd0, dma_read_desc_len}),
        .s_axis_read_desc_tag(dma_read_desc_tag),
        .s_axis_read_desc_id(8'd0),
        .s_axis_read_desc_dest(8'd0),
        .s_axis_read_desc_user(1'b0),
        .s_axis_read_desc_valid(dma_read_desc_valid),
        .s_axis_read_desc_ready(dma_read_desc_ready),
        .m_axis_read_desc_status_tag(),
        .m_axis_read_desc_status_error(),
        .m_axis_read_desc_status_valid(),

        // 读流数据输出 -> 直接环回给写流数据输入
        .m_axis_read_data_tdata(dma_axis_data),
        .m_axis_read_data_tkeep(dma_axis_keep),
        .m_axis_read_data_tvalid(dma_axis_valid),
        .m_axis_read_data_tready(dma_axis_ready),
        .m_axis_read_data_tlast(dma_axis_last),
        .m_axis_read_data_tid(),
        .m_axis_read_data_tdest(),
        .m_axis_read_data_tuser(),

        // 写描述符通道
        .s_axis_write_desc_addr(dma_write_desc_addr),
        .s_axis_write_desc_len({4'd0, dma_write_desc_len}),
        .s_axis_write_desc_tag(dma_write_desc_tag),
        .s_axis_write_desc_valid(dma_write_desc_valid),
        .s_axis_write_desc_ready(dma_write_desc_ready),
        .m_axis_write_desc_status_len(),
        .m_axis_write_desc_status_tag(),
        .m_axis_write_desc_status_id(),
        .m_axis_write_desc_status_dest(),
        .m_axis_write_desc_status_user(),
        .m_axis_write_desc_status_error(),
        .m_axis_write_desc_status_valid(),

        // 写流数据输入 <- 接读流数据输出
        .s_axis_write_data_tdata(dma_axis_data),
        .s_axis_write_data_tkeep(dma_axis_keep),
        .s_axis_write_data_tvalid(dma_axis_valid),
        .s_axis_write_data_tready(dma_axis_ready),
        .s_axis_write_data_tlast(dma_axis_last),
        .s_axis_write_data_tid(8'd0),
        .s_axis_write_data_tdest(8'd0),
        .s_axis_write_data_tuser(1'b0),

        // AXI Master 发起总线接口
        .m_axi_awid(dma_axi_awid),
        .m_axi_awaddr(dma_axi_awaddr),
        .m_axi_awlen(dma_axi_awlen),
        .m_axi_awsize(dma_axi_awsize),
        .m_axi_awburst(dma_axi_awburst),
        .m_axi_awlock(dma_axi_awlock),
        .m_axi_awcache(dma_axi_awcache),
        .m_axi_awprot(dma_axi_awprot),
        .m_axi_awvalid(dma_axi_awvalid),
        .m_axi_awready(dma_axi_awready),
        .m_axi_wdata(dma_axi_wdata),
        .m_axi_wstrb(dma_axi_wstrb),
        .m_axi_wlast(dma_axi_wlast),
        .m_axi_wvalid(dma_axi_wvalid),
        .m_axi_wready(dma_axi_wready),
        .m_axi_bid(dma_axi_bid),
        .m_axi_bresp(dma_axi_bresp),
        .m_axi_bvalid(dma_axi_bvalid),
        .m_axi_bready(dma_axi_bready),
        .m_axi_arid(dma_axi_arid),
        .m_axi_araddr(dma_axi_araddr),
        .m_axi_arlen(dma_axi_arlen),
        .m_axi_arsize(dma_axi_arsize),
        .m_axi_arburst(dma_axi_arburst),
        .m_axi_arlock(dma_axi_arlock),
        .m_axi_arcache(dma_axi_arcache),
        .m_axi_arprot(dma_axi_arprot),
        .m_axi_arvalid(dma_axi_arvalid),
        .m_axi_arready(dma_axi_arready),
        .m_axi_rid(dma_axi_rid),
        .m_axi_rdata(dma_axi_rdata),
        .m_axi_rresp(dma_axi_rresp),
        .m_axi_rlast(dma_axi_rlast),
        .m_axi_rvalid(dma_axi_rvalid),
        .m_axi_rready(dma_axi_rready),
        .enable(1'b1)
    );

    // ==============================================================
    // 模块 2: AXI Crossbar 2x2 互联矩阵
    // ==============================================================
    axi_crossbar #(
        .S_COUNT(S_COUNT),
        .M_COUNT(M_COUNT),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .S_ID_WIDTH(ID_WIDTH),
        // 地址空间译码：M1 为 4KB (12位), M0 为 32KB (15位)
        .M_ADDR_WIDTH({32'd12, 32'd15}),
        // 基地址映射：M1 在 0x0001_0000, M0 在 0x0000_0000
        .M_BASE_ADDR({32'h0001_0000, 32'h0000_0000}),
        .M_CONNECT_READ(4'b1111),
        .M_CONNECT_WRITE(4'b1111)
    ) u_crossbar (
        .clk(clk),
        .rst(rst),

        // S_AXI 接口 (向量拼接：高位接 DMA，低位接 TB)
        .s_axi_awid({dma_axi_awid, s_axi_awid}),
        .s_axi_awaddr({dma_axi_awaddr, s_axi_awaddr}),
        .s_axi_awlen({dma_axi_awlen, s_axi_awlen}),
        .s_axi_awsize({dma_axi_awsize, s_axi_awsize}),
        .s_axi_awburst({dma_axi_awburst, s_axi_awburst}),
        .s_axi_awlock({dma_axi_awlock, s_axi_awlock}),
        .s_axi_awcache({dma_axi_awcache, s_axi_awcache}),
        .s_axi_awprot({dma_axi_awprot, s_axi_awprot}),
        .s_axi_awuser({2{1'b0}}),
        .s_axi_awvalid({dma_axi_awvalid, s_axi_awvalid}),
        .s_axi_awready({dma_axi_awready, s_axi_awready}),

        .s_axi_wdata({dma_axi_wdata, s_axi_wdata}),
        .s_axi_wstrb({dma_axi_wstrb, s_axi_wstrb}),
        .s_axi_wlast({dma_axi_wlast, s_axi_wlast}),
        .s_axi_wuser({2{1'b0}}),
        .s_axi_wvalid({dma_axi_wvalid, s_axi_wvalid}),
        .s_axi_wready({dma_axi_wready, s_axi_wready}),

        .s_axi_bid({dma_axi_bid, s_axi_bid}),
        .s_axi_bresp({dma_axi_bresp, s_axi_bresp}),
        .s_axi_buser(),
        .s_axi_bvalid({dma_axi_bvalid, s_axi_bvalid}),
        .s_axi_bready({dma_axi_bready, s_axi_bready}),

        .s_axi_arid({dma_axi_arid, s_axi_arid}),
        .s_axi_araddr({dma_axi_araddr, s_axi_araddr}),
        .s_axi_arlen({dma_axi_arlen, s_axi_arlen}),
        .s_axi_arsize({dma_axi_arsize, s_axi_arsize}),
        .s_axi_arburst({dma_axi_arburst, s_axi_arburst}),
        .s_axi_arlock({dma_axi_arlock, s_axi_arlock}),
        .s_axi_arcache({dma_axi_arcache, s_axi_arcache}),
        .s_axi_arprot({dma_axi_arprot, s_axi_arprot}),
        .s_axi_aruser({2{1'b0}}),
        .s_axi_arvalid({dma_axi_arvalid, s_axi_arvalid}),
        .s_axi_arready({dma_axi_arready, s_axi_arready}),

        .s_axi_rid({dma_axi_rid, s_axi_rid}),
        .s_axi_rdata({dma_axi_rdata, s_axi_rdata}),
        .s_axi_rresp({dma_axi_rresp, s_axi_rresp}),
        .s_axi_rlast({dma_axi_rlast, s_axi_rlast}),
        .s_axi_ruser(),
        .s_axi_rvalid({dma_axi_rvalid, s_axi_rvalid}),
        .s_axi_rready({dma_axi_rready, s_axi_rready}),

        // M_AXI 接口 (高位分给 M1/Adapter，低位分给 M0/axi_ram)
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

    // ==============================================================
    // 模块 3: 高速 AXI4 RAM (挂在 M0 端口，大小 32KB)
    // ==============================================================
    axi_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(15), // 2^15 = 32KB
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

    // ==============================================================
    // 模块 4: AXI4 到 AXI-Lite 跨协议桥 (挂在 M1 端口)
    // ==============================================================
    axi_axil_adapter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ID_WIDTH(M_ID_WIDTH),
        .AXIL_DATA_WIDTH(32),
        .CONVERT_BURST(1),
        .CONVERT_NARROW(1)
    ) u_bridge (
        .clk(clk),
        .rst(rst),
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

        // 桥转换后的 AXI-Lite 接口
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

    // ==============================================================
    // 模块 5: 低速 32 位 AXI-Lite RAM (大小 4KB)
    // ==============================================================
    axil_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12) // 2^12 = 4KB
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

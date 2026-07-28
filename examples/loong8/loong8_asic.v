// loong8 ASIC 顶层 — 用于 RTL→GDSII 流程验证
// 裁剪版：小 SRAM、无 FPGA 原语
`timescale 1ns/1ps
`include "defs.vh"

module loong8_asic (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led,
    output wire        uart_txd
);
    // 时钟使能（25MHz from 50MHz /2）
    reg cpu_clk_div;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) cpu_clk_div <= 0;
        else cpu_clk_div <= ~cpu_clk_div;
    wire cpu_clk_en = cpu_clk_div;

    // ===== 小规模存储（ASIC 友好）=====
    // ROM 128B  + SRAM 128B
    reg [7:0] rom [0:127];
    reg [7:0] sram_data [0:127];
    
    reg [15:0] inst_data_raw;
    reg [7:0]  mem_rdata_raw;
    reg [15:0] mem_addr_r;
    wire [15:0] sram_base = 16'h0800;
    wire [15:0] code_top  = 16'h0880;  // 128 bytes

    // CPU 总线
    wire [15:0] inst_addr, mem_addr, mem_raddr, inst_data;
    wire        mem_rd, mem_wr;
    wire [7:0]  mem_wdata, mem_rdata;
    wire        mem_fault;
    assign inst_data = inst_data_raw;
    assign led = mem_rdata;

    // 地址译码
    wire [7:0] mem_page = mem_addr[15:8];
    wire mmio_uart  = (mem_page == 8'hC0 && mem_addr[7:4] == 4'h0);
    wire mmio_uartr = (mem_addr_r[15:8] == 8'hC0 && mem_addr_r[7:4] == 4'h0);
    wire mmio_hole  = (mem_page == 8'hC0) && !mmio_uart;

    // 取指（ROM 直接取，SRAM 作为数据区）
    always @(posedge clk) begin
        if (inst_addr < 128)
            inst_data_raw <= {rom[inst_addr + 1], rom[inst_addr]};
        else
            inst_data_raw <= 16'h0000;
    end

    // 数据读
    wire [7:0] sram_rdata;
    assign sram_rdata = (mem_addr_r >= sram_base && mem_addr_r < sram_base + 512) ?
        sram_data[mem_addr_r - sram_base] : 8'h00;
    always @(posedge clk) begin
        mem_addr_r <= mem_addr;
    end

    // 数据写
    wire sram_wr = mem_wr && mem_addr >= sram_base && mem_addr < sram_base + 512;
    always @(posedge clk)
        if (sram_wr) sram_data[mem_addr - sram_base] <= mem_wdata;

    // MMIO 读
    always @(posedge clk) begin
        if (mmio_uartr) mem_rdata_raw <= 8'h00;
        else mem_rdata_raw <= sram_rdata;
    end
    assign mem_rdata = mem_rdata_raw;
    assign mem_fault = mmio_hole;

    // UART TX stub
    reg uart_tx_busy;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) uart_tx_busy <= 0;
        else if (mem_wr && mmio_uart) uart_tx_busy <= 1;
        else uart_tx_busy <= 0;
    assign uart_txd = 1'b1;

    cpu_core cpu (
        .clk(clk), .rst_n(rst_n), .cpu_clk_en(cpu_clk_en),
        .irq_pending(1'b0), .irq_ack(),
        .inst_addr(inst_addr), .inst_data(inst_data),
        .mem_addr(mem_addr), .mem_raddr(mem_raddr),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_fault(mem_fault),
        .dbg_pc(), .dbg_ir(), .dbg_tick(),
        .dbg_r1(), .dbg_r2()
    );
endmodule

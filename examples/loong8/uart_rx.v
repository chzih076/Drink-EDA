// loong8 UART 接收器
// 9600-8-N-1，与 uart_tx.v 共用同一组波特率参数
// MMIO: 0xC000=RX DATA(读), 0xC001=STAT(bit1=RX ready)
module uart_rx (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rx,           // 串行输入
    output reg  [7:0]   rx_data,      // 接收数据寄存器
    output reg          rx_ready,     // RX 就绪（读后自动清除）
    input  wire         rx_ack        // CPU 读应答（清除 rx_ready）
);
    parameter BAUD_DIV = 10417; // 100MHz / 9600（与 uart_tx 一致）

    reg [13:0] baud_cnt;
    wire       baud_tick;

    // 波特率发生器（共用）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
        end else if (baud_cnt >= BAUD_DIV - 1) begin
            baud_cnt <= 0;
        end else begin
            baud_cnt <= baud_cnt + 1;
        end
    end
    assign baud_tick = (baud_cnt == (BAUD_DIV >> 1));  // 中间采样点

    // ===== RX 状态机 =====
    localparam IDLE  = 3'h0;
    localparam START = 3'h1;  // 检测到起始位，等半个位到中间采样
    localparam DATA  = 3'h2;  // 接收 8 位数据
    localparam STOP  = 3'h3;  // 停止位
    localparam DONE  = 3'h4;  // 数据就绪

    reg [2:0] state;
    reg [7:0] shift;     // 移位寄存器
    reg [3:0] bit_cnt;   // 已接收位数

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            shift <= 8'h00;
            bit_cnt <= 4'd0;
            rx_data <= 8'h00;
            rx_ready <= 1'b0;
        end else begin
            // CPU 读应答清除 ready
            if (rx_ack) rx_ready <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx) begin          // 检测起始位（下降沿）
                        state <= START;
                        bit_cnt <= 4'd0;
                    end
                end

                START: begin
                    if (baud_tick) begin    // 半个位周期后到中间采样点
                        if (!rx) begin      // 确认是起始位
                            state <= DATA;
                            bit_cnt <= 4'd0;
                        end else begin
                            state <= IDLE;  // 毛刺，忽略
                        end
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        shift <= {rx, shift[7:1]};  // LSB 先行
                        bit_cnt <= bit_cnt + 4'd1;
                        if (bit_cnt == 4'd7) begin
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    rx_data <= shift;      // 锁存接收数据
                    rx_ready <= 1'b1;       // 标记就绪
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

// loong8 UART 发送器
// 默认 100MHz / 9600 ≈ 10417，可通过参数覆盖

module uart_tx (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [7:0]   tx_data,
    input  wire         tx_wr,
    output reg          tx_busy,
    output reg          txd         // 串行输出
);

    parameter BAUD_DIV = 10417; // 100MHz / 9600

    reg [13:0] baud_cnt;
    reg       baud_tick;
    reg [3:0] bit_cnt;
    reg [9:0] shift;  // {stop, data[7:0], start}

    // 波特率发生器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end else if (baud_cnt >= BAUD_DIV - 1) begin
            baud_cnt <= 0;
            baud_tick <= 1;
        end else begin
            baud_cnt <= baud_cnt + 1;
            baud_tick <= 0;
        end
    end

    // 发送状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift <= 10'h3FF;  // 空闲状态：高电平
            bit_cnt <= 0;
            tx_busy <= 0;
            txd <= 1;
        end else if (tx_wr && !tx_busy) begin
            // 加载发送数据
            shift <= {1'b1, tx_data, 1'b0};  // stop + data + start
            bit_cnt <= 10;
            tx_busy <= 1;
        end else if (tx_busy && baud_tick) begin
            txd <= shift[0];
            shift <= {1'b1, shift[9:1]};
            if (bit_cnt == 1) begin
                tx_busy <= 0;
            end
            bit_cnt <= bit_cnt - 1;
        end else if (!tx_busy) begin
            txd <= 1;
        end
    end

endmodule

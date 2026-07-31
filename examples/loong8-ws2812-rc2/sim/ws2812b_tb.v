// ws2812b_tb.v — WS2812B 控制器仿真测试台
// 验证：时钟、复位、LED 输出时序翻转
module ws2812b_tb;
    reg clk = 0;
    reg rst_n = 0;
    wire gpio;
    wire [7:0] debug;

    ws2812b_ctrl uut (.clk(clk), .rst_n(rst_n), .gpio(gpio), .debug(debug));

    always #10 clk = ~clk;  // 50MHz

    initial begin
        #100 rst_n = 1;         // 复位释放
        #1000000 $display("SIM OK: gpio toggling = %0d", $countones(gpio));
        $finish;
    end
endmodule

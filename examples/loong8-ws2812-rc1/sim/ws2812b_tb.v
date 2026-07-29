// ws2812b_tb.v — WS2812B 时序验证
`timescale 1ns/1ps

module ws2812b_tb;
    reg clk = 0, rst_n = 0;
    wire gpio;
    wire [7:0] debug;

    always #10 clk = ~clk;

    initial begin
        $dumpfile("ws2812b.vcd");
        $dumpvars(0, ws2812b_tb);
    end

    ws2812b_ctrl uut (.clk(clk), .rst_n(rst_n), .gpio(gpio), .debug(debug));

    // 只在 GPIO 变化时报告
    initial begin
        #100 rst_n = 1;
        $display("复位完成");
        $monitor("%0tns  GPIO=%b  debug=%0d", $time, gpio, debug);
        #5000000;  // 5ms
        $display("仿真完成 @ %0tns", $time);
        $finish;
    end
endmodule

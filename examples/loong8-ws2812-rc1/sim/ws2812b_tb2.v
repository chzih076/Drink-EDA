`timescale 1ns/1ps
module ws2812b_tb;
    reg clk=0, rst_n=0;
    wire gpio;
    wire [7:0] debug;
    always #10 clk = ~clk;
    
    ws2812b_ctrl uut(.*);
    
    initial begin
        $dumpfile("ws2812b2.vcd");
        $dumpvars(0, ws2812b_tb);
        #100 rst_n = 1;
        $display("t=%0t rst_n=1 brightness=%0d", $time, uut.brightness);
        #2000000;  // 2ms
        $display("t=%0t brightness=%0d gpio=%b", $time, uut.brightness, gpio);
        #1000000;  // 3ms
        $display("t=%0t brightness=%0d gpio=%b", $time, uut.brightness, gpio);
        #1000000;  // 4ms
        $display("t=%0t brightness=%0d", $time, uut.brightness);
        #1000000;  // 5ms
        $display("t=%0t brightness=%0d", $time, uut.brightness);
        $finish;
    end
endmodule

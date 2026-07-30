module check();
    initial begin
        $dumpfile("ws2812b_check.vcd");
        $dumpvars(0, ws2812b_tb.uut);
        
        // 等复位完成后检查时钟分频
        #200;
        
        // 检查 WS2812B 时序
        #50000;  // 大约一个 bit 周期
        $display("=== 时序检查 @ %0t ===", $time);
        
        #1000000;  // 1ms
        $display("=== 1ms 检查 @ %0t ===", $time);
        
        #1000000;  // 2ms
        $display("=== 2ms 检查 @ %0t ===", $time);
        
        $finish;
    end
endmodule

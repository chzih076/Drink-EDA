// WS2812B LED 控制器 — loong8 最小系统演示
// 50MHz → 800KHz WS2812B 时序
// 内置呼吸灯效果（PWM 亮度渐变）
// <200 cells，无需编程

module ws2812b_ctrl (
    input  wire        clk,        // 50MHz
    input  wire        rst_n,      // 异步复位
    output wire        gpio,       // WS2812B 数据输出（带片上拉）
    output wire [7:0]  debug       // 调试：当前状态/颜色
);
    // ---- 时钟分频：50MHz → 800KHz (周期 62.5 × 64 = 62 计数) ----
    reg [5:0] clk_cnt;
    wire clk_800k = (clk_cnt == 62);  // 50MHz / (62+1) ≈ 800KHz
    always @(posedge clk or negedge rst_n)
        if (!rst_n) clk_cnt <= 0;
        else if (clk_800k) clk_cnt <= 0;
        else clk_cnt <= clk_cnt + 1;

    // ---- WS2812B bit 时序（每个 bit = 64 clk_800k = 80μs）----
    // T0H = 0.35μs ≈ 3 clk_800k
    // T1H = 0.70μs ≈ 9 clk_800k
    // TOT = 1.25μs ≈ 16 clk_800k
    reg [4:0] bit_cnt;           // 每个 bit 内的时钟计数 (0-31)
    reg [4:0] bit_pos;           // 当前发送的 bit 位置 (0-23)
    reg [23:0] color_reg;        // 24-bit 颜色寄存器

    // ---- 呼吸灯效果：颜色渐变 ----
    reg [7:0] brightness;        // 亮度 (0-255)
    reg [15:0] fade_cnt;         // 渐变计数器
    reg fade_dir;                // 渐变方向 (0=变亮, 1=变暗)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 0; bit_pos <= 0; color_reg <= 24'h000000;
            brightness <= 0; fade_cnt <= 0; fade_dir <= 0;
        end else begin
            // ---- 呼吸灯渐变 ----
            fade_cnt <= fade_cnt + 1;
            if (fade_cnt == 50000) begin  // 每 1ms 调整一次
                fade_cnt <= 0;
                if (fade_dir == 0) begin  // 变亮
                    if (brightness == 255) fade_dir <= 1;
                    else brightness <= brightness + 1;
                end else begin            // 变暗
                    if (brightness == 0) fade_dir <= 0;
                    else brightness <= brightness - 1;
                end
            end

            // ---- 颜色生成（红色呼吸灯）----
            // 使用 ADD/SUB 风格：Red = 亮度渐变，Green = 0，Blue = 0
            // 这演示了 loong8 的运算思想
            color_reg[23:16] <= brightness;   // Red: 呼吸
            color_reg[15:8]  <= 8'h00;        // Green: 固定 0
            color_reg[7:0]   <= brightness;   // Blue: 同步呼吸 → 紫色

            // ---- WS2812B 时序发生器 ----
            if (clk_800k) begin
                if (bit_cnt < 31) begin
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    bit_cnt <= 0;
                    if (bit_pos == 23) bit_pos <= 0;
                    else bit_pos <= bit_pos + 1;
                end
            end
        end
    end

    // ---- WS2812B 输出 ----
    // bit 当前正在发送的位
    wire bit_val = color_reg[23 - bit_pos];

    // 时序：T0H=3, T1H=9, TOT=16
    // bit=0: 前 3 个时钟高，后 13 个时钟低
    // bit=1: 前 9 个时钟高，后 7 个时钟低
    reg gpio_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) gpio_out <= 0;
        else begin
            if (clk_800k) begin
                if (bit_val) begin  // Bit 1: T1H=9
                    gpio_out <= (bit_cnt < 9);
                end else begin      // Bit 0: T0H=3
                    gpio_out <= (bit_cnt < 3);
                end
            end
        end
    end

    // ---- 输出 ----
    // GPIO 带上拉效果：空闲时高电平
    assign gpio = gpio_out;

    // 调试：当前颜色值
    assign debug = brightness;
endmodule

`timescale 1ns/1ps
// loong8 CPU 单周期 — 统一 LUT 内存架构（无 DPU，无 pipeline）
// 取指+译码+执行全在同一周期完成，无 ir_q/inst_pc 寄存器
// 全部地址空间都是组合读，无 ld_pending
// MMIO (0xC000+) 通过 dpu_soc 的 MMIO 寄存器组组合读
`include "defs.vh"
module cpu_core (
    input  wire         clk, rst_n, cpu_clk_en, irq_pending,
    output wire         irq_ack,
    output wire [15:0]  inst_addr,
    input  wire [15:0]  inst_data,
    output wire [15:0]  mem_addr,
    output wire [15:0]  mem_raddr,
    output wire         mem_rd,
    output reg          mem_wr,
    output reg  [7:0]   mem_wdata,
    input  wire [7:0]   mem_rdata,
    input  wire         mem_fault,
    output wire [15:0]  dbg_pc, dbg_ir,
    output wire [63:0]  dbg_tick,
    output wire [1:0]   dbg_state,
    output wire [7:0]   dbg_r1,dbg_r2,dbg_r3,dbg_r4,dbg_r5,dbg_r6,dbg_r10,
    output wire [7:0]   dbg_ecfg,output wire dbg_mem_wr,
    output wire [15:0]  dbg_mem_addr,output wire [7:0] dbg_mem_wdata,
    output wire [7:0]   dbg_wrdata,dbg_alu_r,output wire [3:0] dbg_opcode,
    output wire [15:0]  wr_addr
);
    reg [15:0] sp; reg [15:0] ra,kra; reg [7:0] addr_ext,stack_page;
    reg [7:0] crmd,ecfg,estat; reg [15:0] era,badv,freq_ctl;
    reg [15:0] mem_vaddr,pc; reg [63:0] tick_count;
    reg [7:0] r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15;

    assign dbg_pc=pc;
    assign dbg_tick=tick_count;
    assign dbg_ir=inst_data;
    assign dbg_state=2'h1;
    assign dbg_mem_wr=mem_wr;
    assign dbg_mem_addr=mem_vaddr;
    assign dbg_mem_wdata=mem_wdata;
    assign dbg_r1=r1; assign dbg_r2=r2; assign dbg_r3=r3;
    assign dbg_r4=r4; assign dbg_r5=r5; assign dbg_r6=r6;
    assign dbg_r10=r10;
    assign dbg_ecfg=ecfg;

    // 所有指令字段均直接来自组合输入 inst_data（无 pipeline）
    wire [3:0] op=inst_data[15:12];
    wire [3:0] alu_rd=inst_data[11:8],alu_rs=inst_data[7:4],alu_fn=inst_data[3:0];
    wire [3:0] alui_rd=inst_data[11:8],alui_imm=inst_data[7:4],alui_op=inst_data[3:0];
    wire [3:0] mrd=inst_data[11:8],mrs=inst_data[7:4];
    wire [1:0] mw=inst_data[3:2],mo=inst_data[1:0];
    wire [3:0] mxr=inst_data[11:8];wire [1:0] mxs=inst_data[1:0];wire [5:0] mxo=inst_data[7:2];
    wire [2:0] bc=inst_data[11:9];
    wire [3:0] brs=inst_data[8:5];
    wire [1:0] brt=inst_data[4:3];wire [11:0] i12=inst_data[11:0];
    wire [3:0] cra=inst_data[3:0];wire is_eret=(cra==4'h0);
    wire [3:0] mvo=inst_data[3:0],mvd=inst_data[11:8],mvs=inst_data[7:4];
    wire [7:0] blo=inst_data[7:0];wire [2:0] blt=inst_data[11:9];
    reg [31:0] rand_state; wire [31:0] rand_next;
    assign rand_next = rand_state * 32'd1103515245 + 32'd12345;
    wire [7:0] pg=inst_data[11:4];
    wire bnez_is_bwd = (inst_data[4:0] >= 5'd16);
    wire [15:0] bnez_bwd_delta  = (16'd32 - {11'b0, inst_data[4:0]}) << 1;
    wire [15:0] bnez_fwd_delta  = {10'b0, inst_data[4:0], 1'b0};
    wire [15:0] beq_bwd_delta   = (16'd8 - {13'b0, inst_data[2:0]}) << 1;
    wire [15:0] beq_fwd_delta   = {12'b0, inst_data[2:0], 1'b0};

    function [7:0] rd;input [3:0] a;
        case(a) 4'h0:rd=0;4'h1:rd=r1;4'h2:rd=r2;4'h3:rd=r3;4'h4:rd=r4;
            4'h5:rd=r5;4'h6:rd=r6;4'h7:rd=r7;4'h8:rd=r8;4'h9:rd=r9;
            4'hA:rd=r10;4'hB:rd=r11;4'hC:rd=r12;4'hD:rd=r13;4'hE:rd=r14;
            4'hF:rd=r15;default:rd=0;endcase
    endfunction
    function [7:0] alu;input [3:0] f;input [7:0] a,b;
        case(f) 4'h0:alu=a+b;4'h1:alu=a-b;4'h2:alu=a&b;4'h3:alu=a|b;
            4'h4:alu=a^b;4'h5:alu=a<<b;4'h6:alu=a>>b;4'h7:alu=$signed(a)>>>b;
            4'h8:alu=($signed(a)<$signed(b))?8'h01:8'h00;
            4'h9:alu=(a<b)?8'h01:8'h00;4'hA:alu=~(a|b);
            4'hE:alu=0;4'hF:alu=0;default:alu=0;endcase
    endfunction
    function [3:0] alui_f; input [3:0] o;
        case(o) 0:alui_f=0;1:alui_f=2;2:alui_f=3;3:alui_f=4;
               4:alui_f=8;5:alui_f=5;6:alui_f=6;default:alui_f=0;endcase
    endfunction
    task wre;input [3:0] a;input [7:0] d;
        case(a) 4'h0:;4'h1:r1<=d;4'h2:r2<=d;4'h3:r3<=d;4'h4:r4<=d;
            4'h5:r5<=d;4'h6:r6<=d;4'h7:r7<=d;4'h8:r8<=d;4'h9:r9<=d;
            4'hA:r10<=d;4'hB:r11<=d;4'hC:r12<=d;4'hD:r13<=d;4'hE:r14<=d;
            4'hF:r15<=d;default:;endcase
    endtask

    wire [3:0] ra1=(op==4'h0)?alu_rd:(op==4'h1)?alui_rd:(op==4'h2)?mrs:(op==4'h3)?mrd:
                   (op==4'h4)?brs:(op==4'h7)?mrd:(op==4'h9)?mvd:(op==4'hB)?mxr:(op==4'hC)?{2'h0,mxs}:4'h0;
    wire [3:0] ra2=(op==4'h0)?alu_rs:(op==4'h3)?mrs:(op==4'h4)?{2'h0,brt}:
                   (op==4'h7)?mvs:(op==4'h9)?mvs:(op==4'hB)?{2'h0,mxs}:4'h0;
    wire [7:0] v1, v2;
    assign v1 = (ra1==4'h0)?8'h00:(ra1==4'h1)?r1:(ra1==4'h2)?r2:(ra1==4'h3)?r3:
                (ra1==4'h4)?r4:(ra1==4'h5)?r5:(ra1==4'h6)?r6:(ra1==4'h7)?r7:
                (ra1==4'h8)?r8:(ra1==4'h9)?r9:(ra1==4'hA)?r10:(ra1==4'hB)?r11:
                (ra1==4'hC)?r12:(ra1==4'hD)?r13:(ra1==4'hE)?r14:(ra1==4'hF)?r15:8'h00;
    assign v2 = (ra2==4'h0)?8'h00:(ra2==4'h1)?r1:(ra2==4'h2)?r2:(ra2==4'h3)?r3:
                (ra2==4'h4)?r4:(ra2==4'h5)?r5:(ra2==4'h6)?r6:(ra2==4'h7)?r7:
                (ra2==4'h8)?r8:(ra2==4'h9)?r9:(ra2==4'hA)?r10:(ra2==4'hB)?r11:
                (ra2==4'hC)?r12:(ra2==4'hD)?r13:(ra2==4'hE)?r14:(ra2==4'hF)?r15:8'h00;

    wire [15:0] ld_addr   = (op==4'h2) ? {addr_ext, v1+{6'h00,mo}} :
                            (op==4'hC) ? {addr_ext, rd({2'h0,mxs})+{2'h0,mxo}} : 16'h0000;
    wire [7:0]  ld_result = mem_rdata;

    wire [15:0] st_addr   =
        (op==4'h3) ? {addr_ext, v2+{6'h00,mo}} :
        (op==4'hB) ? {addr_ext, rd({2'h0,mxs})+{2'h0,mxo}} :
        (op==4'h9 && mvo==4'h6) ? {stack_page, sp-8'h01} : 16'h0000;

    assign irq_ack = 1'b0;
    assign inst_addr = pc;
    assign wr_addr = mem_vaddr;
    assign mem_addr = mem_vaddr;
    assign mem_raddr = (op==4'h2 || op==4'hC) ? ld_addr :
                       (op==4'h3 || op==4'hB) ? st_addr :
                       (op==4'h9 && mvo==4'h6) ? {stack_page, sp-8'h01} :
                       (op==4'h9 && mvo==4'h7) ? {stack_page, sp} : 16'h0000;
    assign mem_rd = (op==4'h2) || (op==4'hC) || (op==4'h9 && mvo==4'h7);
    wire [7:0] bnez_rs_w = (brs==4'h2)?r2:(brs==4'h1)?r1:rd(brs);
    wire       bnez_cond_w = |bnez_rs_w;

    /* verilator lint_off WIDTH */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc<=16'h0000;tick_count<=64'h0;sp<=8'h00;ra<=16'h0000;kra<=16'h0000;
            addr_ext<=8'h00;stack_page<=8'h00;
            crmd<=8'h00;ecfg<=8'h00;estat<=8'h00;era<=16'h0000;badv<=16'h0000;freq_ctl<=16'h8000;
            mem_wr<=1'b0;mem_vaddr<=16'h0000;mem_wdata<=8'h00;
            r1<=0;r2<=0;r3<=0;r4<=0;r5<=0;r6<=0;r7<=0;r8<=0;r9<=0;r10<=0;r11<=0;r12<=0;r13<=0;r14<=0;r15<=0;
            rand_state<=32'h12345678;
        end else begin
            if (cpu_clk_en) begin
            mem_wr<=1'b0; tick_count<=tick_count+64'h1;
            case (op)
                4'h0: begin if(alu_fn<=4'hA)wre(alu_rd,alu(alu_fn,v1,v2));else if(alu_fn==4'hB)begin wre(alu_rd,rand_next[23:16]);rand_state<=rand_next;end pc<=pc+16'h2;end
                4'h1: begin if(alui_op<=4'h6)wre(alui_rd,alu(alui_f(alui_op),v1,{4'h0,alui_imm}));pc<=pc+16'h2;end
                4'h2: begin
                    mem_vaddr<=ld_addr;
                    wre(mrd,ld_result);
                    if (mw == 2'h1) wre(mrd+4'h1, 8'h00);
                    if (mw == 2'h2) begin wre(mrd+4'h1, 8'h00); wre(mrd+4'h2, 8'h00); wre(mrd+4'h3, 8'h00); end
                    pc<=pc+16'h2;
                end
                 4'h3: begin
                    mem_vaddr<=st_addr;mem_wdata<=v1;
                    mem_wr<=1'b1;
                    pc<=pc+16'h2;
                end
                4'h4: case(bc)
                    3'h0:if(v1==v2)begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h1:if(v1!=v2)begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h2:if($signed(v1)<$signed(v2))begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h3:if($signed(v1)>=$signed(v2))begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h4:if(v1<v2)begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h5:if(v1>=v2)begin if(inst_data[2])pc<=pc+2-beq_bwd_delta;else pc<=pc+2+beq_fwd_delta;end else pc<=pc+2;
                    3'h6:if(v1==8'h00)begin if(bnez_is_bwd)pc<=pc+2-bnez_bwd_delta;else pc<=pc+2+bnez_fwd_delta;end else pc<=pc+2;
                    3'h7:begin if(bnez_cond_w)begin if(bnez_is_bwd)pc<=pc-bnez_bwd_delta;else pc<=pc+2+bnez_fwd_delta;end else pc<=pc+2;end
                    default:pc<=pc+2;endcase
                4'h5:begin pc<=pc+{{3{i12[11]}},i12,1'b0}; end
                4'h6:begin ra<=pc+16'h2;kra<=pc+16'h2;pc<=pc+{{3{i12[11]}},i12,1'b0};end
                4'h7:begin
                    if(is_eret)begin crmd[3]<=1'b1;pc<=era;end else begin
                        if(mvs!=4'h0)/*verilator lint_off CASEINCOMPLETE*/case(cra)
                            4'h0:crmd<=v2;4'h2:ecfg<=v2;4'h4:era<={rd(mvs+4'h1),v2};4'h5:badv<={rd(mvs+4'h1),v2};4'h8:begin freq_ctl<={8'h00,v2};end
                            4'hB:addr_ext<=v2;4'hC:stack_page<=v2;4'hD:ra[7:0]<=v2;4'hE:ra[15:8]<=v2;4'hF:kra<={rd(mvs+4'h1),v2};endcase/*verilator lint_on CASEINCOMPLETE*/
                        if(mrd!=4'h0)/*verilator lint_off CASEINCOMPLETE*/case(cra)
                            4'h0:wre(mrd,crmd);4'h2:wre(mrd,ecfg);4'h3:wre(mrd,estat);4'h4:wre(mrd,era[7:0]);
                            4'h5:wre(mrd,badv[7:0]);4'h8:wre(mrd,freq_ctl[7:0]);4'hB:wre(mrd,addr_ext);4'hC:wre(mrd,stack_page);
                            4'hD:wre(mrd,ra[7:0]);4'hE:wre(mrd,ra[15:8]);4'hF:wre(mrd,kra[7:0]);default:wre(mrd,8'h00);endcase
                        pc<=pc+2;end
                end
                4'h9:/*verilator lint_off CASEINCOMPLETE*/case(mvo)
                    4'h0:begin wre(mvd,v2);pc<=pc+2;end
                    4'h1:begin wre(mvd,~v2);pc<=pc+2;end
                    4'h2:begin wre(mvd,-v2);pc<=pc+2;end
                    4'h3:begin wre(mvd,v2);pc<=pc+2;end
                    4'h4:begin wre(mvd,v2);pc<=pc+2;end
                    4'h5:begin wre(mvd,v2);wre(mvs,v1);pc<=pc+2;end
                4'h6:begin mem_vaddr<={stack_page,sp-8'h01};mem_wdata<=v1;mem_wr<=1'b1;
                      sp<=sp-8'h01;pc<=pc+2;end
                4'h7:begin mem_vaddr<={stack_page,sp};
                      wre(mvd, mem_rdata);
                      sp<=sp+8'h01;pc<=pc+2;end
                    4'h8:begin kra<=pc+2;pc<={addr_ext,v2};end
                    4'h9:pc<=kra;
                    4'hA:begin wre(mvd,sp);pc<=pc+2;end
                    4'hB:begin sp<=v2;pc<=pc+2;end
                    4'hE:pc<=ra;
                    4'hF:begin estat<=8'h01;era<=pc;crmd[3]<=1'b0;pc<={4'h0,ecfg[7:4],8'h00};end
                    default:pc<=pc+2;endcase
                4'hA: begin addr_ext<=pg;pc<=pc+2;end
                4'hB:begin mem_vaddr<={addr_ext,rd({2'h0,mxs})+{2'h0,mxo}};mem_wdata<=v1;
                      mem_wr<=1'b1; pc<=pc+2;end
                4'hC:begin mem_vaddr<={addr_ext,rd({2'h0,mxs})+{2'h0,mxo}};
                      wre(mxr, mem_rdata);
                      pc<=pc+2;end
                4'hD:begin
                    if(blt<=2'h1)begin
                        if((blt==2'h0&&v1==8'h00)||(blt==2'h1&&v1!=8'h00))if(blo[7])pc<=pc+2-((9'd256 - {1'b0, blo}) << 1);else pc<=pc+2+({8'b0, blo, 1'b0});
                        else pc<=pc+2;end
                    else if(blt[2:1]==2'b10) begin: scmp_block
                        reg [15:0] scmp_rd;
                        scmp_rd = {2'h0, inst_data[9:8]};
                        pc<=pc+2;end
                    else pc<=pc+2;end
                default:pc<=pc+2;endcase
        end
        end
    end
    /* verilator lint_on WIDTH */
    assign dbg_alu_r=alu(alu_fn,8'h00,8'h00);
    assign dbg_opcode=op;
    assign dbg_wrdata=8'h00;
endmodule

// loong8 ISA 定义头文件
// 与 Rust 版 decode.rs + cpu.rs 对齐

// ==================== 指令编码 ====================
// Opcodes (4-bit, bits[15:12])
`define OP_ALU   4'h0
`define OP_ALUI  4'h1
`define OP_LD    4'h2
`define OP_ST    4'h3
`define OP_B     4'h4
`define OP_JMP   4'h5
`define OP_JAL   4'h6
`define OP_CSR   4'h7
`define OP_MOVE  4'h9
`define OP_PAGE  4'hA
`define OP_STX   4'hB
`define OP_LDX   4'hC
`define OP_BL    4'hD

// ==================== ALU funct (opcode=0, bits[3:0]) ====================
`define ALU_ADD  4'h0
`define ALU_SUB  4'h1
`define ALU_AND  4'h2
`define ALU_OR   4'h3
`define ALU_XOR  4'h4
`define ALU_SLL  4'h5
`define ALU_SRL  4'h6
`define ALU_SRA  4'h7
`define ALU_SLT  4'h8
`define ALU_SLTU 4'h9
`define ALU_NOR  4'hA
`define ALU_RAND 4'hB
`define ALU_DIV  4'hE
`define ALU_MOD  4'hF

// ==================== ALUI op (opcode=1, bits[3:0]) ====================
`define ALUI_ADDI  4'h0
`define ALUI_ANDI  4'h1
`define ALUI_ORI   4'h2
`define ALUI_XORI  4'h3
`define ALUI_SLTI  4'h4
`define ALUI_SLLI  4'h5
`define ALUI_SRLI  4'h6

// ==================== Branch cond (opcode=4, bits[11:9]) ====================
`define B_BEQ  3'h0
`define B_BNE  3'h1
`define B_BLT  3'h2
`define B_BGE  3'h3
`define B_BLTU 3'h4
`define B_BGEU 3'h5
`define B_BEQZ 3'h6
`define B_BNEZ 3'h7

// ==================== CSR op (opcode=7) ====================
`define CSR_CRMD      4'h0
`define CSR_PRMD      4'h1
`define CSR_ECFG      4'h2
`define CSR_ESTAT     4'h3
`define CSR_ERA       4'h4
`define CSR_BADV      4'h5
`define CSR_FREQ_CTL  4'h8
`define CSR_ADDR_EXT  4'hB
`define CSR_STACK_PAGE 4'hC
`define CSR_RA_LOW    4'hD
`define CSR_RA_HIGH   4'hE
`define CSR_KRA       4'hF

// ==================== MOVE op (opcode=9, bits[3:0]) ====================
`define MOVE_MOVE  4'h0
`define MOVE_NOT   4'h1
`define MOVE_NEG   4'h2
`define MOVE_EXTZB 4'h3
`define MOVE_EXTSB 4'h4
`define MOVE_SWAP  4'h5
`define MOVE_PUSH  4'h6
`define MOVE_POP   4'h7
`define MOVE_JALR  4'h8
`define MOVE_RETR  4'h9
`define MOVE_SPRD  4'hA
`define MOVE_SPWR  4'hB
`define MOVE_RET   4'hE
`define MOVE_ECALL 4'hF

// ==================== Exception codes ====================
`define EXC_INTERRUPT   3'h0
`define EXC_SYSCALL     3'h1
`define EXC_PAGE_FAULT  3'h2
`define EXC_MEM_ERROR   3'h3
`define EXC_ILLEGAL_INST 3'h4

// ==================== Exception vector offsets ====================
`define VEC_INTERRUPT   12'h000
`define VEC_SYSCALL     12'h040
`define VEC_PAGE_FAULT  12'h080
`define VEC_MEM_ERROR   12'h0C0
`define VEC_ILLEGAL_INST 12'h100

// ==================== Width encoding ====================
`define WIDTH_B 2'h0
`define WIDTH_H 2'h1
`define WIDTH_W 2'h2

// ==================== State machine states ====================
`define STATE_FETCH      2'h0
`define STATE_EXECUTE    2'h1
`define STATE_EXCEPTION  2'h2
`define STATE_MEMWAIT    2'h3  // For LD/ST multi-cycle

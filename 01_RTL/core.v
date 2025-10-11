module core #( // DO NOT MODIFY INTERFACE!!!
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) ( 
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output [2:0] o_status, 
    output       o_status_valid,

    // Memory IOs
    output [ADDR_WIDTH-1:0] o_addr,
    output [DATA_WIDTH-1:0] o_wdata,
    output                  o_we,
    input  [DATA_WIDTH-1:0] i_rdata
);

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

    localparam S_IDLE   = 3'b000;
    localparam S_FETCH  = 3'b001;
    localparam S_DECODE = 3'b010;
    localparam S_ALU    = 3'b011;
    localparam S_WRITE  = 3'b100;
    localparam S_PCGEN  = 3'b101;
    localparam S_END    = 3'b110;
    localparam S_BUFF   = 3'b111;

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //

    reg        is_eof;
    reg        o_we_r;
    reg        o_status_valid_r;
    reg        pc_gen_r;
    reg        branch_taken_r;
    reg        jalr_taken_r;
    reg [2:0]  type_r;
    reg [2:0]  state_r;
    reg [2:0]  next_state_r;
    reg [4:0]  alu_ctrl_r;
    reg [4:0]  rd_addr_r;
    reg [31:0] o_addr_r;
    reg [31:0] inst_r;
    reg [31:0] alu_output_r;
    reg [31:0] o_wdata_r;
    reg [31:0] rd_data_r;
    reg [31:0] branch_target_r;
    reg [31:0] jalr_target_r;

    wire        imm_en_w;
    wire        write_en_w;
    wire        invalid_w;
    wire        fp_invalid_w;
    wire        read_fp_en_w;
    wire        write_fp_en_w;
    wire [2:0]  type_w;
    wire [4:0]  rs1_addr_w;
    wire [4:0]  rs2_addr_w;
    wire [4:0]  rd_addr_w;
    wire [4:0]  alu_ctrl_w;
    wire [31:0] alu_output_w;
    wire [31:0] fp_alu_output_w;
    wire [31:0] rs1_data_w;
    wire [31:0] rs2_data_w;
    wire [31:0] pc_w;
    wire [31:0] imm_w;
    wire [31:0] alu_data2_w = (imm_en_w) ? imm_w : rs2_data_w;
    wire        is_load_w    = alu_ctrl_w == 5'b00010;
    wire        is_fp_load_w = alu_ctrl_w == 5'b01101;

    program_counter pc(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_branch_taken(branch_taken_r),
        .i_jalr_taken(jalr_taken_r),
        .i_pc_gen(pc_gen_r),
        .i_branch_target(branch_target_r),
        .i_jalr_target(jalr_target_r),
        .o_pc(pc_w)
    );

    control_unit ctrl(
        .i_inst(inst_r),
        .o_type(type_w),
        .o_imm(imm_w),
        .o_alu_ctrl(alu_ctrl_w),
        .o_rs1_addr(rs1_addr_w),
        .o_rs2_addr(rs2_addr_w),
        .o_rd_addr(rd_addr_w),
        .o_imm_en(imm_en_w),
        .o_fp_en(read_fp_en_w)
    );

    register_file reg_file(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_read_fp_en(read_fp_en_w),
        .i_write_fp_en(write_fp_en_w),
        .i_rs1_addr(rs1_addr_w),
        .i_rs2_addr(rs2_addr_w),
        .i_rd_addr(rd_addr_r),
        .i_rd_data(rd_data_r),
        .i_write_en(write_en_w || (is_load_w && state_r == S_IDLE && ~write_fp_en_w)),
        .o_rs1_data(rs1_data_w),
        .o_rs2_data(rs2_data_w)
    );

    alu alu(
        .i_pc(pc_w),
        .i_data_r1(rs1_data_w), 
        .i_data_r2(alu_data2_w), 
        .i_alu_ctrl(alu_ctrl_r), 
        .o_data(alu_output_w), 
        .o_invalid(invalid_w)
    );

    fp_alu fp_alu(
        .i_data_r1(rs1_data_w),
        .i_data_r2(rs2_data_w),
        .i_alu_ctrl(alu_ctrl_r),
        .o_data(fp_alu_output_w),
        .o_invalid(fp_invalid_w)
    );

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

    assign o_we            = o_we_r;
    assign o_addr          = o_addr_r;
    assign o_wdata         = o_wdata_r;
    assign write_fp_en_w   = (state_r == S_PCGEN) && (type_r != 2) && (type_r != 3) && 
                           ((alu_ctrl_r == 5'b01010) || (alu_ctrl_r == 5'b01011) || (alu_ctrl_r == 5'b01101));
    assign branch_target_w = pc_w + imm_w;
    assign jalr_target_w   = alu_output_w & (~32'h1);
    assign write_en_w      = (state_r == S_PCGEN) && (type_r != 2) && (type_r != 3) && ~write_fp_en_w;
    assign o_status        = type_r;
    assign o_status_valid  = o_status_valid_r;

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

    always @(*) begin
        next_state_r = state_r;
        case (state_r)
            S_IDLE:   next_state_r = S_BUFF;
            S_BUFF:   next_state_r = S_FETCH;
            S_FETCH:  next_state_r = S_DECODE;
            S_DECODE: next_state_r = S_ALU;
            S_ALU:    next_state_r = S_WRITE;
            S_WRITE:  next_state_r = S_PCGEN;
            S_PCGEN:  next_state_r = (is_eof || type_r == 6) ? S_END : S_IDLE;
            S_END:    next_state_r = S_END;
            default:  next_state_r = S_IDLE;
        endcase
    end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            is_eof           <= 0;
            o_we_r           <= 0;
            o_status_valid_r <= 0;
            type_r           <= 0;
            state_r          <= S_IDLE;
            alu_ctrl_r       <= 0;
            rd_addr_r        <= 0;
            o_addr_r         <= 0;
            inst_r           <= 0;
            alu_output_r     <= 0;
            o_wdata_r        <= 0;
            rd_data_r        <= 0;
            pc_gen_r         <= 0;
            branch_taken_r   <= 0;
            jalr_taken_r     <= 0;
            branch_target_r  <= 0;
            jalr_target_r    <= 0;
        end
        else begin
            state_r <= next_state_r;
            case (state_r)
                S_IDLE: begin
                    o_we_r           <= 0;
                    o_addr_r         <= pc_w;
                    pc_gen_r         <= 0;
                    o_status_valid_r <= 0;
                end 
                S_BUFF: begin
                    
                end
                S_FETCH: begin
                    inst_r <= i_rdata;
                    pc_gen_r <= 0;
                end
                S_DECODE: begin
                    if (alu_ctrl_w == 5'b10000) begin
                        is_eof <= 1;
                        type_r <= 6;
                    end
                    else begin
                        alu_ctrl_r <= alu_ctrl_w;
                        rd_addr_r  <= rd_addr_w;   
                        type_r     <= type_w;
                    end
                end
                S_ALU: begin
                    alu_output_r <= (read_fp_en_w) ? fp_alu_output_w : alu_output_w;
                    if (invalid_w || fp_invalid_w) begin
                        type_r           <= 5;
                        o_status_valid_r <= 1;
                    end
                    else begin
                        if (type_r == 2) begin
                            o_we_r    <= 1;
                            o_addr_r  <= (read_fp_en_w) ? fp_alu_output_w : alu_output_w;
                            o_wdata_r <= rs2_data_w;
                        end
                        else if (is_load_w || is_fp_load_w) begin
                            o_we_r   <= 0;
                            o_addr_r <= (read_fp_en_w) ? fp_alu_output_w : alu_output_w;
                        end
                    end
                end
                S_WRITE: begin
                    o_we_r           <= 0;
                    o_status_valid_r <= 1;
                    
                    // JALR stores PC+4
                    if (alu_ctrl_r == 5'b00110) begin
                        rd_data_r <= pc_w + 4;
                    end
                    // Other operations that write to register
                    else if (type_r != 2 && type_r != 3 && !is_load_w && !is_fp_load_w) begin
                        rd_data_r <= alu_output_r;
                    end
                    pc_gen_r <= 1;
                    // Branch logic
                    if (type_r == 3) begin
                        branch_taken_r  <= alu_output_r[0];
                        branch_target_r <= pc_w + imm_w;
                    end
                    else begin
                        branch_taken_r <= 0;
                    end
                    
                    // JALR logic
                    if (alu_ctrl_r == 5'b00110) begin
                        jalr_taken_r  <= 1;
                        jalr_target_r <= alu_output_r & (~32'h1);
                    end
                    else begin
                        jalr_taken_r <= 0;
                    end
                end
                S_PCGEN: begin
                    // Load operations - get data from memory
                    if (is_load_w || is_fp_load_w) begin
                        rd_data_r <= i_rdata;
                    end
                    o_status_valid_r <= 0;
                    pc_gen_r <= 0;
                end
                S_END: begin
                    o_status_valid_r <= 1;
                end
            endcase
        end
    end    
endmodule

module register_file (
    input         i_clk,
    input         i_rst_n,
    input         i_read_fp_en,
    input         i_write_fp_en,
    input [4:0]   i_rs1_addr,
    input [4:0]   i_rs2_addr,
    input [4:0]   i_rd_addr,
    input [31:0]  i_rd_data,
    input         i_write_en,
    output [31:0] o_rs1_data,
    output [31:0] o_rs2_data

);

    reg signed [31:0] x_r  [0:31];
    reg [31:0] fp_r [0:31];
    integer i;

    assign o_rs1_data = (i_read_fp_en) ? fp_r[i_rs1_addr] : x_r[i_rs1_addr];
    assign o_rs2_data = (i_read_fp_en) ? fp_r[i_rs2_addr] : x_r[i_rs2_addr];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                x_r[i]  <= 0;
                fp_r[i] <= 0;
            end
        end
        else begin
            if (i_write_en) x_r[i_rd_addr]     <= i_rd_data;
            if (i_write_fp_en) fp_r[i_rd_addr] <= i_rd_data;
        end
    end

endmodule

module program_counter (
    input         i_clk,
    input         i_rst_n,
    input         i_branch_taken,
    input         i_jalr_taken,
    input         i_pc_gen,
    input  [31:0] i_branch_target,
    input  [31:0] i_jalr_target,
    output [31:0] o_pc
);
    reg  [31:0] pc_r;
    wire [31:0] pc_next_r;
    assign pc_next_r = (i_branch_taken) ? i_branch_target : 
                       (i_jalr_taken)   ? i_jalr_target   : pc_r + 4;
    assign o_pc = pc_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            pc_r <= 0;
        end
        else begin
            if (i_pc_gen) pc_r <= pc_next_r;
        end
    end
    
endmodule

module control_unit (
    input  [31:0] i_inst,
    output [2:0]  o_type,
    output [31:0] o_imm,
    output [4:0]  o_alu_ctrl,
    output [4:0]  o_rs1_addr,
    output [4:0]  o_rs2_addr,
    output [4:0]  o_rd_addr,
    output        o_imm_en,
    output        o_fp_en
);
    reg  [2:0]  o_type_r;
    reg  [4:0]  o_alu_ctrl_r;
    reg  [4:0]  o_rs1_addr_r;
    reg  [4:0]  o_rs2_addr_r;
    reg  [4:0]  o_rd_addr_r;
    reg  [31:0] o_imm_r;
    reg         o_fp_en_r;
    reg         o_imm_en_r;
    wire [6:0]  i_op     = i_inst[6:0];
    wire [6:0]  i_funct7 = i_inst[31:25];
    wire [2:0]  i_funct3 = i_inst[14:12];

    assign o_type     = o_type_r;
    assign o_alu_ctrl = o_alu_ctrl_r;
    assign o_rs1_addr = o_rs1_addr_r;
    assign o_rs2_addr = o_rs2_addr_r;
    assign o_rd_addr  = o_rd_addr_r;
    assign o_imm_en   = o_imm_en_r;
    assign o_fp_en    = o_fp_en_r;
    assign o_imm      = o_imm_r;

    always @(*) begin
        o_alu_ctrl_r = 0;
        o_rs1_addr_r = 0;
        o_rs2_addr_r = 0;
        o_imm_r      = 0;
        o_fp_en_r    = 0;
        o_imm_en_r   = 0;
        o_rd_addr_r  = 0;
        case (i_op)
            `OP_SUB, `OP_SLT, `OP_SRL: begin  // R type
                case (i_funct3)
                    `FUNCT3_SUB: o_alu_ctrl_r = 5'b00000;
                    `FUNCT3_SLT: o_alu_ctrl_r = 5'b01000;
                    `FUNCT3_SRL: o_alu_ctrl_r = 5'b01001;
                    default: o_alu_ctrl_r = 5'b11111; // error code
                endcase
                o_rs1_addr_r = i_inst[19:15];
                o_rs2_addr_r = i_inst[24:20];
                o_rd_addr_r  = i_inst[11:7];
                o_type_r = 0;
            end 
            `OP_ADDI: begin
                o_alu_ctrl_r = 5'b00001;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:20]};
                o_rs1_addr_r = i_inst[19:15];
                o_rd_addr_r  = i_inst[11:7];
                o_type_r     = 1;
            end
            `OP_LW: begin 
                o_alu_ctrl_r = 5'b00010;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:20]};
                o_rs1_addr_r = i_inst[19:15];
                o_rd_addr_r  = i_inst[11:7];
                o_type_r     = 1;
            end
            `OP_SW: begin
                o_alu_ctrl_r = 5'b00011;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
                o_rs1_addr_r = i_inst[19:15];
                o_rs2_addr_r = i_inst[24:20];
                o_type_r     = 2;
            end
            `OP_BEQ, `OP_BLT: begin
                if (i_funct3 == `FUNCT3_BEQ) o_alu_ctrl_r = 5'b00100;
                else o_alu_ctrl_r = 5'b00101;
                o_imm_en_r   = 0;
                o_imm_r      = {{19{i_inst[31]}}, i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
                o_rs1_addr_r = i_inst[19:15];
                o_rs2_addr_r = i_inst[24:20];
                o_type_r     = 3;
            end
            `OP_JALR: begin
                o_alu_ctrl_r = 5'b00110;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:20]};
                o_rs1_addr_r = i_inst[19:15];
                o_rd_addr_r  = i_inst[11:7];
                o_type_r     = 1;
            end
            `OP_AUIPC: begin
                o_alu_ctrl_r = 5'b00111;
                o_imm_en_r   = 1;
                o_imm_r      = {i_inst[31:12], 12'b0};
                o_rd_addr_r  = i_inst[11:7];
                o_type_r     = 4;
            end
            `OP_FSUB, `OP_FMUL, `OP_FCVTWS, `OP_FCLASS: begin
                case (i_funct7)
                    `FUNCT7_FSUB:   o_alu_ctrl_r = 5'b01010;
                    `FUNCT7_FMUL:   o_alu_ctrl_r = 5'b01011;
                    `FUNCT7_FCVTWS: o_alu_ctrl_r = 5'b01100;
                    `FUNCT7_FCLASS: o_alu_ctrl_r = 5'b01111;
                    default: o_alu_ctrl_r = 5'b11111; // error code
                endcase
                o_rs1_addr_r = i_inst[19:15];
                o_rs2_addr_r = i_inst[24:20];
                o_rd_addr_r  = i_inst[11:7];
                o_fp_en_r    = 1;
                o_type_r     = 0;
            end
            `OP_FLW: begin
                o_alu_ctrl_r = 5'b01101;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:20]};
                o_rs1_addr_r = i_inst[19:15];
                o_rd_addr_r  = i_inst[11:7];
                o_fp_en_r    = 0;
                o_type_r     = 1;
            end
            `OP_FSW: begin 
                o_alu_ctrl_r = 5'b01110;
                o_imm_en_r   = 1;
                o_imm_r      = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
                o_rs1_addr_r = i_inst[19:15];
                o_rs2_addr_r = i_inst[24:20];
                o_fp_en_r    = 0;
                o_type_r     = 2;
            end
            `OP_EOF: begin
                o_alu_ctrl_r = 5'b10000;
                o_type_r     = 6;
            end
            default: o_alu_ctrl_r = 5'b11111; // error code
        endcase
    end

endmodule

module alu (
    input         [31:0] i_pc,
    input  signed [31:0] i_data_r1,
    input  signed [31:0] i_data_r2,              // imm is always here
    input         [4:0]  i_alu_ctrl,
    output signed [31:0] o_data,
    output               o_invalid
);

    reg  signed [31:0] o_data_r;
    wire signed [32:0] temp_r1_w = {i_data_r1[31], i_data_r1};
    wire signed [32:0] temp_r2_w = {i_data_r2[31], i_data_r2};
    wire signed [32:0] diff_w = temp_r1_w - temp_r2_w;
    wire signed [32:0] addi_w = temp_r1_w + temp_r2_w;

    assign o_data = o_data_r;
    assign o_invalid = (i_alu_ctrl == 5'b00000) ? (diff_w[32] ^ diff_w[31]) : 
                       (i_alu_ctrl == 5'b00001) ? (addi_w[32] ^ addi_w[31]) : 0;

    always @(*) begin
        case (i_alu_ctrl)
            5'b00000: o_data_r = diff_w[31:0];                             // SUB
            5'b00001: o_data_r = addi_w[31:0];                             // ADDI
            5'b00010: o_data_r = addi_w[31:0];                             // LW
            5'b00011: o_data_r = addi_w[31:0];                             // SW
            5'b00100: o_data_r = {{31{1'b0}}, (i_data_r1 == i_data_r2)};   // BEQ
            5'b00101: o_data_r = {{31{1'b0}}, (i_data_r1 < i_data_r2)};    // BLT
            5'b00110: o_data_r = addi_w[31:0];                             // JALR
            5'b00111: o_data_r = i_pc + i_data_r2;                         // AUIPC
            5'b01000: o_data_r = {{31{1'b0}}, (i_data_r1 < i_data_r2)};    // SLT
            5'b01001: o_data_r = ($unsigned(i_data_r1) >> i_data_r2[4:0]); // SRL
            // 5'b01010: o_data_r = fp_sub(i_data_r1, i_data_r2);          // FSUB
            // 5'b01011: o_data_r = fp_mul(i_data_r1, i_data_r2);          // FMUL
            // 5'b01100: o_data_r = fp_cvtws(i_data_r1);                   // FCVTWS
            5'b01101: o_data_r = addi_w;                                   // FLW
            5'b01110: o_data_r = addi_w;                                   // FSW
            // 5'b01111: o_data_r = fp_class(i_data_r1)                    // FCLASS
            5'b10000: o_data_r = 0;                                        // EOF
            default: o_data_r = 0;
        endcase
    end

endmodule

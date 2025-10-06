
module fp_alu (
    input  [31:0] i_data_a,
    input  [31:0] i_data_b,
    input  [4:0]  i_inst,
    output [31:0] o_fp,
    output        o_invalid
);

    reg o_invalid_r;
    reg [31:0] o_fp_r;
    assign o_fp = o_fp_r;
    assign o_invalid = o_invalid_r;

    // =============================================== decoding ============================================ //

    wire        sign_a_w  = i_data_a[31];
    wire        sign_b_w  = i_data_b[31];
    wire [7:0]  exp_a_w   = i_data_a[30:23];
    wire [7:0]  exp_b_w   = i_data_b[30:23];
    wire [23:0] man_a_w   = (exp_a_w == 8'd0) ? {1'b0, i_data_a[22:0]} : {1'b1, i_data_a[22:0]};
    wire [23:0] man_b_w   = (exp_b_w == 8'd0) ? {1'b0, i_data_b[22:0]} : {1'b1, i_data_b[22:0]};

    // ========================================== output selection ======================================== //

    always @(*) begin
        case (i_inst)
            5'b01010: o_fp_r = sub_result_w;
            5'b01011: o_fp_r = mul_result_w;
            default: o_fp_r = o_fp_r;
        endcase
    end

    // ========================================== SUB calculation ========================================= //

    reg         sub_sign_r;
    reg  [7:0]  sub_exp_r;
    reg  [25:0] sub_man_sum_r;
    reg  [24:0] sub_man_norm_r;
    reg  [23:0] sub_man_rounded_r;
    reg  [7:0]  sub_exp_final_r;

    wire        sign_b_eff_w   = ~sign_b_w;
    wire [7:0]  exp_diff_w     = (exp_a_w > exp_b_w) ? (exp_a_w - exp_b_w) : (exp_b_w - exp_a_w);
    wire [7:0]  exp_large_w    = (exp_a_w >= exp_b_w) ? exp_a_w : exp_b_w;
    wire [24:0] man_a_shift_w  = (exp_a_w >= exp_b_w) ? {man_a_w, 1'b0} : ({man_a_w, 1'b0} >> exp_diff_w);
    wire [24:0] man_b_shift_w  = (exp_b_w > exp_a_w)  ? {man_b_w, 1'b0} : ({man_b_w, 1'b0} >> exp_diff_w);

    // ---------------- Mantissa Add/Sub ---------------- //
    always @(*) begin
        if (sign_a_w == sign_b_eff_w) begin
            sub_man_sum_r = man_a_shift_w + man_b_shift_w;
            sub_sign_r    = sign_a_w;
        end else begin
            if (man_a_shift_w >= man_b_shift_w) begin
                sub_man_sum_r = man_a_shift_w - man_b_shift_w;
                sub_sign_r    = sign_a_w;
            end else begin
                sub_man_sum_r = man_b_shift_w - man_a_shift_w;
                sub_sign_r    = sign_b_eff_w;
            end
        end
    end

    // ---------------- Normalization ---------------- //
    always @(*) begin
        sub_exp_r      = exp_large_w;
        sub_man_norm_r = sub_man_sum_r[24:0];

        // Normalize right (overflow)
        if (sub_man_norm_r[24]) begin
            sub_man_norm_r = sub_man_norm_r >> 1;
            sub_exp_r      = sub_exp_r + 1;
        end else begin
            // Normalize left
            while (sub_man_norm_r[23] == 0 && sub_exp_r > 0) begin
                sub_man_norm_r = sub_man_norm_r << 1;
                sub_exp_r      = sub_exp_r - 1;
            end
        end
    end

    // ---------------- Rounding (Round to Nearest Even) ---------------- //
    wire sub_guard_w = sub_man_sum_r[0]; // guard bit
    wire sub_round_w = 1'b0;             // (sticky bit)
    wire sub_lsb_w   = sub_man_norm_r[0];

    always @(*) begin
        sub_man_rounded_r = sub_man_norm_r[23:1];
        sub_exp_final_r   = sub_exp_r;

        // IEEE754: round to nearest even
        if (sub_guard_w && (sub_round_w | sub_lsb_w)) begin
            sub_man_rounded_r = sub_man_rounded_r + 1;

            // mantissa overflow after rounding
            if (sub_man_rounded_r == 24'h1000000) begin
                sub_man_rounded_r = sub_man_rounded_r >> 1;
                sub_exp_final_r   = sub_exp_final_r + 1;
            end
        end
    end

    // ---------------- Exception Detection ---------------- //
    always @(*) begin
        o_invalid_r = 1'b0;

        if (sub_exp_final_r >= 8'hFF) begin
            // overflow → Inf
            sub_exp_final_r   = 8'hFF;
            sub_man_rounded_r = 0;
            o_invalid_r       = 1;
        end
        else if (sub_exp_final_r == 8'h00) begin
            // underflow → 0
            sub_exp_final_r   = 0;
            sub_man_rounded_r = 0;
            o_invalid_r       = 1;
        end
    end

    // ---------------- Output ---------------- //
    wire [31:0] sub_result_w = {sub_sign_r, sub_exp_final_r, sub_man_rounded_r[22:0]};


    // ========================================== MUL calculation ========================================= //

    reg        mul_sign_r;
    reg [8:0]  mul_exp_r;
    reg [47:0] mul_man_raw_r;
    reg [23:0] mul_man_norm_r;
    reg [23:0] mul_man_rounded_r;
    reg [7:0]  mul_exp_final_r;

    always @(*) begin
        // step1: sign & exponent
        mul_sign_r = sign_a_w ^ sign_b_w;
        mul_exp_r  = exp_a_w + exp_b_w - 127;

        // step2: 24x24 multiplication
        mul_man_raw_r = man_a_w * man_b_w;

        // step3: normalization
        if (mul_man_raw_r[47]) begin
            mul_man_norm_r = mul_man_raw_r[47:24];
            mul_exp_r = mul_exp_r + 1;
        end else begin
            mul_man_norm_r = mul_man_raw_r[46:23];
        end

        // ---------------- ROUNDING (Round to nearest even) ---------------- //
        wire guard_w  = (mul_man_raw_r[22]);
        wire round_w  = (mul_man_raw_r[21]);
        wire sticky_w = |mul_man_raw_r[20:0];
        wire lsb_w    = mul_man_norm_r[0];

        mul_man_rounded_r = mul_man_norm_r;
        mul_exp_final_r   = mul_exp_r[7:0];
        o_invalid_r       = 0;

        if (guard_w && (round_w | sticky_w | lsb_w)) begin
            mul_man_rounded_r = mul_man_norm_r + 1;

            if (mul_man_rounded_r == 24'h1000000) begin
                mul_man_rounded_r = mul_man_rounded_r >> 1;
                mul_exp_final_r = mul_exp_final_r + 1;
            end
        end

        // ---------------- CHECK Overflow / Underflow ---------------- //
        if (mul_exp_final_r >= 8'hFF) begin
            mul_exp_final_r   = 8'hFF;
            mul_man_rounded_r = 0;
            o_invalid_r = 1;
        end
        else if (mul_exp_final_r <= 0) begin
            mul_exp_final_r   = 0;
            mul_man_rounded_r = 0;
            o_invalid_r = 1;
        end
    end

    // ---------------- Output ---------------- //
    wire [31:0] mul_result_w = {mul_sign_r, mul_exp_final_r, mul_man_rounded_r[22:0]};

    
endmodule

module fp_alu (
    input  [31:0] i_data_a,
    input  [31:0] i_data_b,
    input  [4:0]  i_inst,
    output [31:0] o_fp,
    output        o_invalid
);

    reg        o_invalid_r;
    reg [31:0] o_fp_r;
    assign o_fp      = o_fp_r;
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
            5'b01100: o_fp_r = fcvtws_result_w;
            default: o_fp_r = o_fp_r;
        endcase
    end

   // ========================================== SUB calculation ========================================= //

    wire        sign_b_eff_w   = ~sign_b_w;
    wire [7:0]  exp_diff_w     = (exp_a_w > exp_b_w) ? (exp_a_w - exp_b_w) : (exp_b_w - exp_a_w);
    wire [7:0]  exp_large_w    = (exp_a_w >= exp_b_w) ? exp_a_w : exp_b_w;

    // padded mantissas (24 bits + 1 guard position)
    wire [24:0] man_a_padded   = {man_a_w, 1'b0}; // 25 bits
    wire [24:0] man_b_padded   = {man_b_w, 1'b0}; // 25 bits

    wire [24:0] man_a_shift_w  = (exp_a_w >= exp_b_w) ? man_a_padded : (man_a_padded >> exp_diff_w);
    wire [24:0] man_b_shift_w  = (exp_b_w >  exp_a_w) ? man_b_padded : (man_b_padded >> exp_diff_w);

    reg  [25:0] sub_man_sum_r;
    reg         sub_sign_r;

    // ---------------- Mantissa Add/Sub ----------------
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

    // ---------------- Normalization ----------------
    reg [7:0]  sub_exp_r;
    reg [24:0] sub_man_norm_r;

    always @(*) begin
        sub_exp_r      = exp_large_w;
        sub_man_norm_r = sub_man_sum_r[24:0];

        // Normalize right (overflow from addition)
        if (sub_man_norm_r[24]) begin
            sub_man_norm_r = sub_man_norm_r >> 1;
            sub_exp_r      = sub_exp_r + 1;
        end else begin
            // Normalize left (result has leading zeros)
            while (sub_man_norm_r[23] == 0 && sub_exp_r > 0) begin
                sub_man_norm_r = sub_man_norm_r << 1;
                sub_exp_r      = sub_exp_r - 1;
            end
        end
    end

    // ---------------- Sticky / Guard / Round computation ----------------
    // guard: the first bit dropped beyond the 23-bit mantissa (we use sub_man_sum_r[0])
    // round: the next bit after guard in the sum (sub_man_sum_r[1])
    // sticky: OR of all bits that were shifted out from the smaller operand during alignment
    //         (i.e., the lower exp_diff_w bits of the operand that was shifted)

    wire sub_guard_w = sub_man_sum_r[0];        // bit right after the LSB of mantissa
    wire sub_round_w = sub_man_sum_r[1];        // next bit after guard (if present)

    // compute sticky from the operand that got shifted (the smaller-exponent operand)
    wire sub_sticky_from_a = (exp_a_w < exp_b_w && exp_diff_w != 0) ? |man_a_padded[exp_diff_w-1:0] : 1'b0;
    wire sub_sticky_from_b = (exp_b_w < exp_a_w && exp_diff_w != 0) ? |man_b_padded[exp_diff_w-1:0] : 1'b0;
    wire sub_sticky_w      = sub_sticky_from_a | sub_sticky_from_b;

    // LSB of the rounded mantissa (before rounding)
    wire sub_lsb_w = sub_man_norm_r[0];

    // ---------------- Exception Detection (detect BEFORE rounding as requested) ----------------
    reg [23:0] sub_man_rounded_r; // prepare for possible assignment later
    reg [7:0]  sub_exp_final_r;

    always @(*) begin
        o_invalid_r = 1'b0;

        // If exponent already saturated or zero after normalization → flag and set canonical outputs.
        if (sub_exp_r >= 8'hFF) begin
            // Overflow -> set to Inf (sign preserved), raise invalid
            sub_exp_final_r   = 8'hFF;
            sub_man_rounded_r = 24'd0;
            o_invalid_r       = 1'b1;
        end
        else if (sub_exp_r == 8'h00) begin
            // Underflow (becoming zero / subnormal handled as zero here), raise invalid
            sub_exp_final_r   = 8'h00;
            sub_man_rounded_r = 24'd0;
            o_invalid_r       = 1'b1;
        end
        else begin
            // No exception → proceed to rounding
            sub_exp_final_r   = sub_exp_r;
            sub_man_rounded_r = sub_man_norm_r[23:1]; // truncate: take top 23 bits as mantissa (plus hidden 1)
            
            // IEEE754: round to nearest even using guard/round/sticky/lsb
            // round-up when guard==1 AND (round==1 OR sticky==1 OR lsb==1)
            if (sub_guard_w && (sub_round_w | sub_sticky_w | sub_lsb_w)) begin
                sub_man_rounded_r = sub_man_rounded_r + 1;

                // mantissa overflow after rounding -> shift right and increment exponent
                if (sub_man_rounded_r == 24'h1000000) begin
                    sub_man_rounded_r = sub_man_rounded_r >> 1;
                    sub_exp_final_r   = sub_exp_final_r + 1;

                    // if rounding caused exponent saturation, signal invalid (overflow)
                    if (sub_exp_final_r >= 8'hFF) begin
                        sub_exp_final_r   = 8'hFF;
                        sub_man_rounded_r = 24'd0;
                        o_invalid_r       = 1'b1;
                    end
                end
            end
        end
    end

    // ---------------- Output (packed) ----------------
    wire [31:0] sub_result_w = {sub_sign_r, sub_exp_final_r, sub_man_rounded_r[22:0]};

    // ========================================== MUL calculation ========================================= //

    reg        mul_sign_r;
    reg [8:0]  mul_exp_r;
    reg [47:0] mul_man_raw_r;
    reg [23:0] mul_man_norm_r;
    reg [23:0] mul_man_rounded_r;
    reg [7:0]  mul_exp_final_r;

    always @(*) begin
        // ---------------- STEP 1: sign & exponent ----------------
        mul_sign_r = sign_a_w ^ sign_b_w;
        mul_exp_r  = exp_a_w + exp_b_w - 127;

        // ---------------- STEP 2: 24x24 mantissa multiplication ----------------
        mul_man_raw_r = man_a_w * man_b_w;  // 48-bit result

        // ---------------- STEP 3: normalization ----------------
        // If product >= 2.0, shift right 1 and increment exponent
        if (mul_man_raw_r[47]) begin
            mul_man_norm_r = mul_man_raw_r[47:24];
            mul_exp_r = mul_exp_r + 1;
        end else begin
            mul_man_norm_r = mul_man_raw_r[46:23];
        end

        // ---------------- STEP 4: Exception detection (before rounding) ----------------
        mul_exp_final_r   = mul_exp_r[7:0];
        mul_man_rounded_r = mul_man_norm_r;
        o_invalid_r       = 1'b0;

        if (mul_exp_final_r >= 8'hFF) begin
            // Overflow → Inf
            mul_exp_final_r   = 8'hFF;
            mul_man_rounded_r = 24'd0;
            o_invalid_r       = 1'b1;
        end
        else if (mul_exp_final_r <= 0) begin
            // Underflow → 0
            mul_exp_final_r   = 8'h00;
            mul_man_rounded_r = 24'd0;
            o_invalid_r       = 1'b1;
        end
        else begin
            // ---------------- STEP 5: Rounding (Round to Nearest Even) ----------------
            // guard: next bit after mantissa
            // round: bit after guard
            // sticky: OR of all remaining lower bits
            wire guard_w  = mul_man_raw_r[22];
            wire round_w  = mul_man_raw_r[21];
            wire sticky_w = |mul_man_raw_r[20:0];
            wire lsb_w    = mul_man_norm_r[0];

            // IEEE754: round to nearest, ties to even
            if (guard_w && (round_w | sticky_w | lsb_w)) begin
                mul_man_rounded_r = mul_man_norm_r + 1;

                // mantissa overflow after rounding, shift & increment exponent
                if (mul_man_rounded_r == 24'h1000000) begin
                    mul_man_rounded_r = mul_man_rounded_r >> 1;
                    mul_exp_final_r   = mul_exp_final_r + 1;

                    // rounding cause exponent overflow,  raise overflow flag
                    if (mul_exp_final_r >= 8'hFF) begin
                        mul_exp_final_r   = 8'hFF;
                        mul_man_rounded_r = 24'd0;
                        o_invalid_r       = 1'b1;
                    end
                end
            end
        end
    end

    // ---------------- Final output ----------------
    wire [31:0] mul_result_w = {mul_sign_r, mul_exp_final_r, mul_man_rounded_r[22:0]};

    // ====================================== FCVTWS calculation ========================================== //

    reg         [55:0] mant_ext_r;
    reg         [55:0] shifted_r;
    reg                guard_r, round_r, sticky_r;
    reg         [55:0] rounded_r;
    reg  signed [31:0] fcvtws_result_r;
    wire signed [31:0] fcvtws_result_w;
    wire signed [8:0]  fcvtws_exp_w = $signed({1'b0, exp_a_w}) - 127;
    integer shift_amt;
    assign fcvtws_result_w = fcvtws_result_r;

    always @(*) begin
        fcvtws_result_r = 0;
        o_invalid_r = 0;

        // special cases
        if (exp_a_w == 8'hFF) begin
            // NaN or Inf
            o_invalid_r = 1;
            if (man_a_w != 0) begin
                // NaN
                fcvtws_result_r = 32'sh7FFFFFFF;
            end
            else begin
                // +Inf / -Inf
                fcvtws_result_r = sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF;
            end
        end
        else if (fcvtws_exp_w < 0) begin
            // smaller than 1
            fcvtws_result_r = 0;
        end
        else if (fcvtws_exp_w > 31) begin
            // overflow
            o_invalid_r = 1;
            fcvtws_result_r = sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF;
        end
        else begin

            mant_ext_r = {1'b1, man_a_w[22:0], 32'b0}; // guarding space
            shift_amt = 32 - fcvtws_exp_w;

            if (shift_amt > 0) begin
                guard_r   = mant_ext_r[shift_amt - 1];
                round_r   = (shift_amt > 1) ? mant_ext_r[shift_amt - 2] : 1'b0;
                sticky_r  = |mant_ext_r[shift_amt - 2:0];
                shifted_r = mant_ext_r >> shift_amt;
            end
            else begin
                guard_r   = 0;
                round_r   = 0;
                sticky_r  = 0;
                shifted_r = mant_ext_r;
            end
            // Round to nearest even
            if (guard_r && (round_r | sticky_r | shifted_r[0])) rounded_r = shifted_r + 1;
            else rounded_r = shifted_r;

            // leading 32 bits
            if (sign_a_w) fcvtws_result_r = -$signed(rounded_r[55:24]);
            else fcvtws_result_r =  $signed(rounded_r[55:24]);
        end
    end
    
endmodule

module fp_alu (
    input  [31:0] i_data_r1,
    input  [31:0] i_data_r2,
    input  [4:0]  i_alu_ctrl,
    output [31:0] o_data,
    output        o_invalid
);

    reg        sub_o_invalid_r;
    reg        mul_o_invalid_r;
    reg        fcvtws_o_invalid_r;
    reg [31:0] o_fp_r;
    assign o_data      = o_fp_r;
    assign o_invalid = (i_alu_ctrl == 5'b01010) ? sub_o_invalid_r :
                       (i_alu_ctrl == 5'b01011) ? mul_o_invalid_r :
                       (i_alu_ctrl == 5'b01100) ? fcvtws_o_invalid_r : 0;

    // =============================================== decoding ============================================ //

    wire        sign_a_w  = i_data_r1[31];
    wire        sign_b_w  = i_data_r2[31];
    wire [7:0]  exp_a_w   = i_data_r1[30:23];
    wire [7:0]  exp_b_w   = i_data_r2[30:23];
    wire [23:0] man_a_w   = (exp_a_w == 8'd0) ? {1'b0, i_data_r1[22:0]} : {1'b1, i_data_r1[22:0]};
    wire [23:0] man_b_w   = (exp_b_w == 8'd0) ? {1'b0, i_data_r2[22:0]} : {1'b1, i_data_r2[22:0]};

    wire        [31:0] sub_result_w;
    wire        [31:0] mul_result_w;
    wire signed [31:0] fcvtws_result_w;
    wire        [31:0] fclass_result_w;

    // ========================================== output selection ======================================== //

    always @(*) begin
        case (i_alu_ctrl)
            5'b01010: o_fp_r = sub_result_w;
            5'b01011: o_fp_r = mul_result_w;
            5'b01100: o_fp_r = fcvtws_result_w;
            5'b01111: o_fp_r = fclass_result_w;
            default: o_fp_r = 0;
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

    // ... inside SUB calculation always @(*) block ...

    // ---------------- Normalization (Corrected Combinational Logic) ----------------
    reg [7:0]  sub_exp_temp;
    reg [7:0]  sub_exp_r;
    reg [24:0] sub_man_temp;
    reg [24:0] sub_man_norm_r;
    integer    shift_amount;

    always @(*) begin
        sub_exp_r = 0;
        sub_man_norm_r = 0;
        sub_exp_temp   = exp_large_w;
        sub_man_temp   = sub_man_sum_r[24:0];
        shift_amount   = 0;

        // Check for zero result first
        if (sub_man_sum_r == 26'd0) begin
            sub_exp_temp = 8'd0;
            sub_man_temp = 25'd0;
        end
        // Normalize right (overflow from addition)
        else if (sub_man_sum_r[25]) begin // Overflow from addition, bit 25 would be set
            sub_man_temp = sub_man_sum_r[25:1]; // Shift right by 1
            sub_exp_temp = sub_exp_temp + 1;
        end
        // Normalize left (result has leading zeros)
        else if (sub_man_sum_r[24] == 0) begin // Hidden bit is 0, requires left shift
            // Use a priority case to find the first '1'
            if (sub_man_temp[23])      shift_amount = 1;
            else if (sub_man_temp[22]) shift_amount = 2;
            else if (sub_man_temp[21]) shift_amount = 3;
            else if (sub_man_temp[20]) shift_amount = 4;
            else if (sub_man_temp[19]) shift_amount = 5;
            else if (sub_man_temp[18]) shift_amount = 6;
            else if (sub_man_temp[17]) shift_amount = 7;
            else if (sub_man_temp[16]) shift_amount = 8;
            else if (sub_man_temp[15]) shift_amount = 9;
            else if (sub_man_temp[14]) shift_amount = 10;
            else if (sub_man_temp[13]) shift_amount = 11;
            else if (sub_man_temp[12]) shift_amount = 12;
            else if (sub_man_temp[11]) shift_amount = 13;
            else if (sub_man_temp[10]) shift_amount = 14;
            else if (sub_man_temp[9])  shift_amount = 15;
            else if (sub_man_temp[8])  shift_amount = 16;
            else if (sub_man_temp[7])  shift_amount = 17;
            else if (sub_man_temp[6])  shift_amount = 18;
            else if (sub_man_temp[5])  shift_amount = 19;
            else if (sub_man_temp[4])  shift_amount = 20;
            else if (sub_man_temp[3])  shift_amount = 21;
            else if (sub_man_temp[2])  shift_amount = 22;
            else if (sub_man_temp[1])  shift_amount = 23;
            else if (sub_man_temp[0])  shift_amount = 24;
            else shift_amount = 25; // Should be all zeros if we reach here, handled by zero check
            // Perform the shift in one go
            sub_man_temp = sub_man_temp << shift_amount;
            sub_exp_temp = sub_exp_temp - shift_amount;
        end

        // Assign to the final registers after all calculations are done
        sub_man_norm_r = sub_man_temp;
        sub_exp_r      = sub_exp_temp;
        
    end

    // ---------------- Sticky / Guard / Round computation ----------------
    // sub_man_norm_r: 25 bits (normalized mantissa including guard bit)
    // sub_man_sum_r: 26 bits (sum or diff before normalization)

    wire sub_guard_w = sub_man_norm_r[0];       // bit right after LSB of mantissa
    wire sub_round_w = sub_man_norm_r[1];       // next bit after guard (if present)
    wire sub_lsb_w   = sub_man_norm_r[0];       // LSB before rounding

    // Sticky from the shifted operand (smaller exponent)
    wire sub_sticky_from_a_w;
    wire sub_sticky_from_b_w;

    genvar j;
    wire [24:0] sticky_a_bits;
    wire [24:0] sticky_b_bits;

    generate
        for (j = 0; j < 25; j = j + 1) begin : gen_sticky_a
            assign sticky_a_bits[j] = (exp_a_w < exp_b_w && j < exp_diff_w) ? man_a_padded[j] : 1'b0;
            assign sticky_b_bits[j] = (exp_b_w < exp_a_w && j < exp_diff_w) ? man_b_padded[j] : 1'b0;
        end
    endgenerate

    assign sub_sticky_from_a_w = |sticky_a_bits;
    assign sub_sticky_from_b_w = |sticky_b_bits;

    wire sub_sticky_w        = sub_sticky_from_a_w | sub_sticky_from_b_w;

    // ---------------- Exception Detection & Rounding ----------------
    reg [23:0] sub_man_rounded_r;
    reg [7:0]  sub_exp_final_r;

    always @(*) begin
        sub_o_invalid_r = 1'b0;

        if (sub_exp_r >= 8'hFF) begin
            // Overflow -> Inf
            sub_exp_final_r   = 8'hFF;
            sub_man_rounded_r = 24'd0;
            sub_o_invalid_r   = 1'b1;
        end
        else if (sub_exp_r == 8'h00) begin
            // Underflow -> zero/subnormal
            if (sub_man_norm_r) begin
                sub_exp_final_r   = 8'h00;
                sub_man_rounded_r = 24'd0;
                sub_o_invalid_r   = 1'b1;
            end
            else begin
                sub_exp_final_r = 0;
                sub_man_rounded_r = 0;
            end
        end
        else begin
            // No exception → rounding
            sub_exp_final_r   = sub_exp_r;
            sub_man_rounded_r = sub_man_norm_r[23:1]; // top 23 bits

            // Round to nearest even
            if (sub_guard_w && (sub_round_w | sub_sticky_w | sub_lsb_w)) begin
                sub_man_rounded_r = sub_man_rounded_r + 1;

                // Mantissa overflow after rounding -> shift right & increment exponent
                if (sub_man_rounded_r == 24'h800000) begin
                    sub_man_rounded_r = sub_man_rounded_r >> 1;
                    sub_exp_final_r   = sub_exp_final_r + 1;

                    if (sub_exp_final_r >= 8'hFF) begin
                        sub_exp_final_r   = 8'hFF;
                        sub_man_rounded_r = 24'd0;
                        sub_o_invalid_r   = 1'b1;
                    end
                end
            end
        end
    end

    // ---------------- Output (packed) ----------------
    assign sub_result_w = {sub_sign_r, sub_exp_final_r, sub_man_rounded_r[22:0]};

    // ========================================== MUL calculation ========================================= //

    reg        mul_sign_r;
    reg [9:0]  mul_exp_r;
    reg [47:0] mul_man_raw_r;
    reg [23:0] mul_man_norm_r;
    reg [23:0] mul_man_rounded_r;
    reg [7:0]  mul_exp_final_r;

    wire mul_guard_w  = mul_man_raw_r[22];
    wire mul_round_w  = mul_man_raw_r[21];
    wire mul_sticky_w = |mul_man_raw_r[20:0];
    wire mul_lsb_w    = mul_man_norm_r[0];

    always @(*) begin
        mul_sign_r         = 0;
        mul_exp_r          = 0;
        mul_exp_final_r    = 0;
        mul_man_raw_r      = 0;
        mul_man_norm_r     = 0;
        mul_man_rounded_r  = 0;
        mul_o_invalid_r    = 0;
        if ((!exp_a_w && !man_a_w) || (!exp_b_w && !man_b_w)) begin
            mul_sign_r = 0;
            mul_exp_final_r = 0;
            mul_man_rounded_r = 0;
        end
        else begin
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
            mul_o_invalid_r       = 1'b0;

            if ($signed(mul_exp_r) >= $signed(9'h0FF)) begin
                // Overflow → Inf
                mul_exp_final_r   = 8'hFF;
                mul_man_rounded_r = 24'd0;
                mul_o_invalid_r   = 1'b1;
            end
            else if ($signed(mul_exp_r) <= 0) begin
                // Underflow → 0
                mul_exp_final_r   = 8'h00;
                mul_man_rounded_r = 24'd0;
                mul_o_invalid_r   = 1'b1;
            end
            else begin
                // ---------------- STEP 5: Rounding (Round to Nearest Even) ----------------
                // guard: next bit after mantissa
                // round: bit after guard
                // sticky: OR of all remaining lower bits

                // IEEE754: round to nearest, ties to even
                if (mul_guard_w && (mul_round_w | mul_sticky_w | mul_lsb_w)) begin
                    mul_man_rounded_r = mul_man_norm_r + 1;

                    // mantissa overflow after rounding, shift & increment exponent
                    if (mul_man_rounded_r == 24'h800000) begin
                        mul_man_rounded_r = mul_man_rounded_r >> 1;
                        mul_exp_final_r   = mul_exp_final_r + 1;

                        // rounding cause exponent overflow,  raise overflow flag
                        if (mul_exp_final_r >= 8'hFF) begin
                            mul_exp_final_r   = 8'hFF;
                            mul_man_rounded_r = 24'd0;
                            mul_o_invalid_r       = 1'b1;
                        end
                    end
                end
            end
        end
    end

    // ---------------- Final output ----------------
    assign mul_result_w = {mul_sign_r, mul_exp_final_r, mul_man_rounded_r[22:0]};

    // ====================================== FCVTWS calculation ========================================== //

    reg         [63:0] mant_ext_r;
    reg         [63:0] shifted_r;
    reg                guard_r, round_r, sticky_r;
    reg         [63:0] rounded_r;
    reg  signed [31:0] fcvtws_result_r;
    wire signed [8:0]  fcvtws_exp_w = $signed({1'b0, exp_a_w}) - 127;
    integer shift_amt, i;
    assign fcvtws_result_w = fcvtws_result_r;

    always @(*) begin
        fcvtws_result_r = 0;
        fcvtws_o_invalid_r = 0;

        if (exp_a_w == 8'hFF) begin
            fcvtws_o_invalid_r = 1;
            fcvtws_result_r = (man_a_w[22:0] != 23'd0) ? 32'sh7FFFFFFF : (sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF);
        end
        else if (fcvtws_exp_w < 0) begin
            fcvtws_result_r = 0;
        end
        else if (fcvtws_exp_w > 31) begin
            fcvtws_o_invalid_r = 1;
            fcvtws_result_r = sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF;
        end
        else begin
            mant_ext_r = {8'b0, 1'b1, man_a_w[22:0], 32'b0}; // 56 bits total
            shift_amt = 55 - fcvtws_exp_w;

            if (shift_amt <= 0) begin
                // No shift needed (large exponent)
                guard_r = 0;
                round_r = 0;
                sticky_r = 0;
                shifted_r = mant_ext_r;
            end 
            else if (shift_amt >= 56) begin
                // Shift everything out (very small number)
                guard_r = 0;
                round_r = 0;
                sticky_r = 0;
                shifted_r = 0;
            end 
            else begin
                // Normal shift
                shifted_r = mant_ext_r >> shift_amt;
                
                // Extract guard bit (first bit shifted out)
                guard_r = mant_ext_r[shift_amt - 1];
                
                // Extract round bit (second bit shifted out)
                round_r = (shift_amt > 1) ? mant_ext_r[shift_amt - 2] : 1'b0;
                
                // Sticky = OR of all bits below round bit
                sticky_r = 0;
                for (i = 0; i < shift_amt - 2 && i < 56; i = i + 1) begin
                    sticky_r = sticky_r | mant_ext_r[i];
                end
            end

            // Round to nearest even
            if (guard_r && (round_r | sticky_r | shifted_r[0])) rounded_r = shifted_r + 1;
            else rounded_r = shifted_r;

            // Convert to signed integer
            if (sign_a_w) fcvtws_result_r = -$signed(rounded_r[31:0]);
            else fcvtws_result_r = $signed(rounded_r[31:0]);
        end
    end


    // ======================================== FCLASS calculation ===================================== //

    reg  [31:0] fclass_result_r;
    assign fclass_result_w = fclass_result_r;

    always @(*) begin
        if (exp_a_w == 8'hFF) begin // Special case: Inf or NaN
            if (man_a_w[22:0] != 23'd0) begin // NaN if mantissa is non-zero
                fclass_result_r = (man_a_w[22]) ? 32'd512 : 32'd256; // Quiet NaN (MSB=1) vs Signaling NaN (MSB=0)
            end else begin // Infinity if mantissa is zero
                fclass_result_r = (sign_a_w) ? 32'd1 : 32'd128; // -Infinity vs +Infinity
            end
        end
        else if (!exp_a_w) begin 
            if (!man_a_w) fclass_result_r = (sign_a_w) ? 8 : 16; // -0; +0
            else fclass_result_r = (sign_a_w) ? 4 : 32; // -SUB; +SUB
        end
        else begin
            fclass_result_r = (sign_a_w) ? 2 : 64; // +NOR; -NOR
        end
    end

    
endmodule
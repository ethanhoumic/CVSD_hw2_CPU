module fp_module (
    input  [31:0] i_data_r1,
    input  [31:0] i_data_r2,
    input  [4:0]  i_alu_ctrl,
    output [31:0] o_data,
    output        o_invalid
);

    reg        sub_o_invalid_r;
    reg        sub_num_invalid_r;
    reg        mul_o_invalid_r;
    reg        mul_num_invalid_r;
    reg        fcvtws_o_invalid_r;
    reg [31:0] o_fp_r;
    assign o_data      = o_fp_r;
    assign o_invalid = (i_alu_ctrl == 5'b01010) ? (sub_o_invalid_r || sub_num_invalid_r) :
                       (i_alu_ctrl == 5'b01011) ? (mul_o_invalid_r || mul_num_invalid_r) :
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

    // Padded mantissas with guard, round, and sticky bits
    wire [26:0] man_a_padded   = {man_a_w, 3'b0}; // 27 bits (24 + 3 for GRS)
    wire [26:0] man_b_padded   = {man_b_w, 3'b0}; // 27 bits

    wire [26:0] man_a_shift_w  = (exp_a_w >= exp_b_w) ? man_a_padded : (man_a_padded >> exp_diff_w);
    wire [26:0] man_b_shift_w  = (exp_b_w >  exp_a_w) ? man_b_padded : (man_b_padded >> exp_diff_w);

    reg  [27:0] sub_man_sum_r;
    reg         sub_sign_r;

    // ---------------- Mantissa Add/Sub ----------------
    always @(*) begin
        sub_num_invalid_r = 0;
        if (exp_a_w >= 8'hff || exp_b_w >= 8'hff) begin
            sub_num_invalid_r = 1;
        end
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
    reg [7:0]  sub_exp_temp;
    reg [7:0]  sub_exp_r;
    reg [26:0] sub_man_temp;
    reg [26:0] sub_man_norm_r;
    reg [7:0]  shift_amount_r;

    always @(*) begin
        sub_exp_r = 0;
        sub_man_norm_r = 0;
        sub_exp_temp   = exp_large_w;
        sub_man_temp   = sub_man_sum_r[26:0];
        shift_amount_r   = 0;

        // Check for zero result first
        if (sub_man_sum_r == 28'd0) begin
            sub_exp_temp = 8'd0;
            sub_man_temp = 27'd0;
        end
        // Normalize right (overflow from addition)
        else if (sub_man_sum_r[27]) begin
            sub_man_temp = sub_man_sum_r[27:1]; // Shift right by 1
            sub_exp_temp = sub_exp_temp + 1;
        end
        // Normalize left (result has leading zeros)
        else if (sub_man_sum_r[26] == 0) begin
            // Find leading 1
            if (sub_man_temp[25])      shift_amount_r = 1;
            else if (sub_man_temp[24]) shift_amount_r = 2;
            else if (sub_man_temp[23]) shift_amount_r = 3;
            else if (sub_man_temp[22]) shift_amount_r = 4;
            else if (sub_man_temp[21]) shift_amount_r = 5;
            else if (sub_man_temp[20]) shift_amount_r = 6;
            else if (sub_man_temp[19]) shift_amount_r = 7;
            else if (sub_man_temp[18]) shift_amount_r = 8;
            else if (sub_man_temp[17]) shift_amount_r = 9;
            else if (sub_man_temp[16]) shift_amount_r = 10;
            else if (sub_man_temp[15]) shift_amount_r = 11;
            else if (sub_man_temp[14]) shift_amount_r = 12;
            else if (sub_man_temp[13]) shift_amount_r = 13;
            else if (sub_man_temp[12]) shift_amount_r = 14;
            else if (sub_man_temp[11]) shift_amount_r = 15;
            else if (sub_man_temp[10]) shift_amount_r = 16;
            else if (sub_man_temp[9])  shift_amount_r = 17;
            else if (sub_man_temp[8])  shift_amount_r = 18;
            else if (sub_man_temp[7])  shift_amount_r = 19;
            else if (sub_man_temp[6])  shift_amount_r = 20;
            else if (sub_man_temp[5])  shift_amount_r = 21;
            else if (sub_man_temp[4])  shift_amount_r = 22;
            else if (sub_man_temp[3])  shift_amount_r = 23;
            else if (sub_man_temp[2])  shift_amount_r = 24;
            else if (sub_man_temp[1])  shift_amount_r = 25;
            else if (sub_man_temp[0])  shift_amount_r = 26;
            else shift_amount_r = 27;
            
            sub_man_temp = sub_man_temp << shift_amount_r;
            sub_exp_temp = sub_exp_temp - shift_amount_r;
        end

        sub_man_norm_r = sub_man_temp;
        sub_exp_r      = sub_exp_temp;
    end

    // ---------------- Guard/Round/Sticky bits ----------------
    // After normalization, sub_man_norm_r has format: [26:24]=integer+mantissa, [2:0]=GRS bits
    wire [3:0] sub_grs_w = sub_man_norm_r[2:0];  // Get lower 3 bits for rounding

    // ---------------- Exception Detection & Rounding ----------------
    reg [22:0] sub_man_rounded_r;
    reg [7:0]  sub_exp_final_r;

    always @(*) begin
        sub_o_invalid_r = 1'b0;

        if (sub_exp_r >= 8'hFF) begin
            // Overflow -> Inf
            sub_exp_final_r   = 8'hFF;
            sub_man_rounded_r = 23'd0;
            sub_o_invalid_r   = 1'b1;
        end
        else if ($signed({1'b0, sub_exp_r}) <= 0) begin
            // Underflow -> zero/subnormal
            if (sub_man_norm_r != 0) begin
                sub_exp_final_r   = 8'h00;
                sub_man_rounded_r = 23'd0;
                sub_o_invalid_r   = 1'b1;
            end
            else begin
                sub_exp_final_r = 0;
                sub_man_rounded_r = 0;
            end
        end
        else begin
            // No exception → rounding using verified logic
            sub_exp_final_r   = sub_exp_r;
            sub_man_rounded_r = sub_man_norm_r[25:3]; // Extract 23-bit mantissa
            
            // Verified rounding logic: check GRS bits
            // GRS format: [2]=Guard, [1]=Round, [0]=Sticky
            if (sub_grs_w > 4'b0100) begin
                // Round up
                sub_man_rounded_r = sub_man_rounded_r + 1;
            end
            else if (sub_grs_w == 4'b0100) begin
                // Tie case: round to even (check LSB)
                if (sub_man_rounded_r[0]) begin
                    sub_man_rounded_r = sub_man_rounded_r + 1;
                end
            end
            // else: round down (do nothing)

            // Check for mantissa overflow after rounding
            if (sub_man_rounded_r == 23'h7FFFFF + 1) begin
                sub_man_rounded_r = 23'd0;
                sub_exp_final_r   = sub_exp_final_r + 1;

                if (sub_exp_final_r >= 8'hFF) begin
                    sub_exp_final_r   = 8'hFF;
                    sub_man_rounded_r = 23'd0;
                    sub_o_invalid_r   = 1'b1;
                end
            end
        end
    end

    // ---------------- Output (packed) ----------------
    assign sub_result_w = (sub_exp_final_r == 0 && sub_man_rounded_r == 0) ? 
                          32'h00000000 : // Force +0 for zero result
                          {sub_sign_r, sub_exp_final_r, sub_man_rounded_r};

    // ========================================== MUL calculation ========================================= //

    reg         mul_sign_r;
    reg  [9:0]  mul_exp_r;
    reg  [47:0] mul_man_raw_r;
    reg  [22:0] mul_man_rounded_r;
    reg  [7:0]  mul_exp_final_r;
    reg  [26:0] mul_man_norm_r;  // 24 bits mantissa + 3 bits GRS
    wire [2:0]  mul_grs_w = mul_man_norm_r[2:0];

    always @(*) begin
        mul_sign_r         = 0;
        mul_exp_r          = 0;
        mul_exp_final_r    = 0;
        mul_man_raw_r      = 0;
        mul_man_rounded_r  = 0;
        mul_o_invalid_r    = 0;
        mul_man_norm_r     = 0;
        mul_num_invalid_r  = 0;
        if (exp_a_w == 8'hff || exp_b_w == 8'hff) begin
            mul_num_invalid_r = 1;
        end
        if ((~|exp_a_w && ~|man_a_w) || (~|exp_b_w && ~|man_b_w)) begin
            // Zero result
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
            // Format: If mul_man_raw_r[47]=1, result is [47:24] with [23:0] as fractional bits
            //         If mul_man_raw_r[46]=1, result is [46:23] with [22:0] as fractional bits
            
            if (mul_man_raw_r[47]) begin
                mul_man_norm_r = mul_man_raw_r[47:21];  // Take top 27 bits
                mul_exp_r = mul_exp_r + 1;
            end else begin
                mul_man_norm_r = mul_man_raw_r[46:20];  // Take top 27 bits (shifted left by 1)
            end

            // ---------------- STEP 4: Exception detection (before rounding) ----------------
            mul_exp_final_r   = mul_exp_r[7:0];
            mul_o_invalid_r   = 1'b0;

            if ($signed(mul_exp_r) >= $signed(10'h0FF)) begin
                // Overflow → Inf
                mul_exp_final_r   = 8'hFF;
                mul_man_rounded_r = 23'd0;
                mul_o_invalid_r   = 1'b1;
            end
            else if ($signed(mul_exp_r) <= 0) begin
                // Underflow → 0
                mul_exp_final_r   = 8'h00;
                mul_man_rounded_r = 23'd0;
                mul_o_invalid_r   = 1'b1;
            end
            else begin
                // ---------------- STEP 5: Rounding (verified logic) ----------------
                
                mul_man_rounded_r = mul_man_norm_r[25:3];  // Extract 23-bit mantissa
                
                // Apply verified rounding logic
                if (mul_grs_w > 3'b100) begin
                    // Round up
                    mul_man_rounded_r = mul_man_rounded_r + 1;
                end
                else if (mul_grs_w == 3'b100) begin
                    // Tie: round to even
                    if (mul_man_rounded_r[0]) begin
                        mul_man_rounded_r = mul_man_rounded_r + 1;
                    end
                end

                // Check mantissa overflow after rounding
                if (mul_man_rounded_r == 23'h7FFFFF + 1) begin
                    mul_man_rounded_r = 23'd0;
                    mul_exp_final_r   = mul_exp_final_r + 1;

                    if (mul_exp_final_r >= 8'hFF) begin
                        mul_exp_final_r   = 8'hFF;
                        mul_man_rounded_r = 23'd0;
                        mul_o_invalid_r   = 1'b1;
                    end
                end
            end
        end
    end

    // ---------------- Final output ----------------
    assign mul_result_w = (mul_exp_final_r == 0 && mul_man_rounded_r == 0) ?
                          32'h00000000 : // Force +0 for zero result
                          {mul_sign_r, mul_exp_final_r, mul_man_rounded_r};

    // ====================================== FCVTWS calculation ========================================== //

    reg         [63:0] mant_ext_r;
    reg         [63:0] shifted_r;
    reg                guard_r, round_r, sticky_r;
    reg         [63:0] rounded_r;
    reg  signed [31:0] fcvtws_result_r;
    reg  signed [6:0]  shift_amt_r;
    wire signed [8:0]  fcvtws_exp_w = $signed({1'b0, exp_a_w}) - 127;
    integer shift_amt, i;
    assign fcvtws_result_w = fcvtws_result_r;

    always @(*) begin
        fcvtws_result_r = 0;
        fcvtws_o_invalid_r = 0;
        shift_amt_r = 0;

        if (exp_a_w == 8'hFF) begin
            fcvtws_o_invalid_r = 1;
            fcvtws_result_r = (man_a_w[22:0] != 23'd0) ? 32'sh7FFFFFFF : (sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF);
        end
        else if (fcvtws_exp_w < -1) begin
            fcvtws_result_r = 0;
        end
        else if (fcvtws_exp_w > 30) begin
            fcvtws_o_invalid_r = 1;
            fcvtws_result_r = sign_a_w ? 32'sh80000000 : 32'sh7FFFFFFF;
        end
        else begin
            mant_ext_r = {8'b0, 1'b1, man_a_w[22:0], 32'b0}; // 64 bits total
            shift_amt_r = 55 - fcvtws_exp_w;
            
            if (shift_amt_r <= 0) begin
                guard_r = 0;
                round_r = 0;
                sticky_r = 0;
                shifted_r = mant_ext_r;
            end 
            else if (shift_amt_r > 56) begin
                guard_r = 0;
                round_r = 0;
                sticky_r = 0;
                shifted_r = 0;
            end 
            else begin
                shifted_r = mant_ext_r >> shift_amt_r;
                guard_r = mant_ext_r[shift_amt_r - 1];
                round_r = (shift_amt_r > 1) ? mant_ext_r[shift_amt_r - 2] : 1'b0;
                
                sticky_r = 0;
                for (i = 0; i < 64; i = i + 1) begin
                    if (i < shift_amt_r - 2) sticky_r = sticky_r | mant_ext_r[i];
                end
            end

            // Round to nearest even using verified logic
            if ({guard_r, round_r, sticky_r} > 3'b100) rounded_r = shifted_r + 1;
            else if ({guard_r, round_r, sticky_r} == 3'b100) begin
                if (shifted_r[0]) rounded_r = shifted_r + 1;
                else rounded_r = shifted_r;
            end
            else rounded_r = shifted_r;

            // Convert to signed integer and check overflow
            if (sign_a_w) begin
                if (rounded_r[31:0] > 32'h80000000) begin
                    fcvtws_o_invalid_r = 1;
                    fcvtws_result_r = 32'sh80000000;
                end
                else fcvtws_result_r = -$signed(rounded_r[31:0]);
            end
            else begin
                if (rounded_r[31]) begin
                    fcvtws_o_invalid_r = 1;
                    fcvtws_result_r = 32'sh7FFFFFFF;
                end
                else fcvtws_result_r = $signed(rounded_r[31:0]);
            end
        end
    end

    // ======================================== FCLASS calculation ===================================== //

    reg  [31:0] fclass_result_r;
    assign fclass_result_w = fclass_result_r;

    always @(*) begin
        if (exp_a_w == 8'hFF) begin
            if (man_a_w[22:0] != 23'd0) begin
                fclass_result_r = (man_a_w[22]) ? 32'd512 : 32'd256;
            end else begin
                fclass_result_r = (sign_a_w) ? 32'd1 : 32'd128;
            end
        end
        else if (~|exp_a_w) begin 
            if (~|man_a_w[22:0]) fclass_result_r = (sign_a_w) ? 32'd8 : 32'd16;
            else fclass_result_r = (sign_a_w) ? 32'd4 : 32'd32;
        end
        else begin
            fclass_result_r = (sign_a_w) ? 32'd2 : 32'd64;
        end
    end
    
endmodule
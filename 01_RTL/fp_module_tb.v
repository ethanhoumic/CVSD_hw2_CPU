`timescale 1ns/1ps
`include "fp_module.v"

module fp_alu_tb;

    // DUT signals
    reg  [31:0] i_data_a;
    reg  [31:0] i_data_b;
    reg  [4:0]  i_inst;
    wire [31:0] o_fp;
    wire        o_invalid;

    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Instantiate DUT
    fp_module dut (
        .i_data_r1(i_data_a),
        .i_data_r2(i_data_b),
        .i_alu_ctrl(i_inst),
        .o_data(o_fp),
        .o_invalid(o_invalid)
    );

    // Helper function to create FP number
    function [31:0] make_fp;
        input sign;
        input [7:0] exp;
        input [22:0] mant;
        begin
            make_fp = {sign, exp, mant};
        end
    endfunction

    // Test verification task
    task verify_result;
        input [31:0] expected;
        input expected_invalid;
        input [200*8:1] test_name;
        begin
            test_count = test_count + 1;
            if (o_fp === expected && o_invalid === expected_invalid) begin
                $display("[PASS] Test %0d: %s", test_count, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %s", test_count, test_name);
                $display("  Expected: %h (invalid=%b)", expected, expected_invalid);
                $display("  Got:      %h (invalid=%b)", o_fp, o_invalid);
                fail_count = fail_count + 1;
            end
            #10;
        end
    endtask

    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display("FP ALU Comprehensive Testbench");
        $display("========================================\n");

        // ========================================
        // FSUB Tests (i_inst = 5'b01010)
        // ========================================
        $display("\n--- Testing FSUB ---");
        i_inst = 5'b01010;

        // Basic arithmetic
        i_data_a = 32'h40A00000; i_data_b = 32'h40400000; #10;
        verify_result(32'h40000000, 1'b0, "FSUB: 5.0 - 3.0 = 2.0");

        i_data_a = 32'h40400000; i_data_b = 32'h40400000; #10;
        verify_result(32'h00000000, 1'b0, "FSUB: 3.0 - 3.0 = 0.0");

        i_data_a = 32'h40000000; i_data_b = 32'h40A00000; #10;
        verify_result(32'hC0400000, 1'b0, "FSUB: 2.0 - 5.0 = -3.0");

        // Edge cases: very small differences
        i_data_a = 32'h3F800001; i_data_b = 32'h3F800000; #10;
        verify_result(32'h34000000, 1'b0, "FSUB: 1.0000001 - 1.0 = 2^-23");

        i_data_a = 32'h3F800010; i_data_b = 32'h3F800000; #10;
        $display("[INFO] FSUB: 1+(16*2^-23) - 1.0 = %h", o_fp);

        // Subnormal results
        i_data_a = 32'h00800001; i_data_b = 32'h00800000; #10;
        $display("[INFO] FSUB: Subnormal - Subnormal = %h", o_fp);

        // Different exponents requiring alignment
        i_data_a = 32'h41200000; i_data_b = 32'h3F800000; #10;
        verify_result(32'h41100000, 1'b0, "FSUB: 10.0 - 1.0 = 9.0");

        i_data_a = 32'h47800000; i_data_b = 32'h3F800000; #10;
        verify_result(32'h477FFF00, 1'b0, "FSUB: 65536 - 1 = 65535");

        // Catastrophic cancellation
        i_data_a = 32'h3F800080; i_data_b = 32'h3F800000; #10;
        $display("[INFO] FSUB: Cancellation test = %h", o_fp);

        // Sign tests
        i_data_a = 32'hC0000000; i_data_b = 32'hC0400000; #10;
        verify_result(32'h3F800000, 1'b0, "FSUB: -2.0 - (-3.0) = 1.0");

        i_data_a = 32'h40000000; i_data_b = 32'hC0000000; #10;
        verify_result(32'h40800000, 1'b0, "FSUB: 2.0 - (-2.0) = 4.0");

        // Overflow cases
        i_data_a = 32'h7F000000; i_data_b = 32'hFF000000; #10;
        verify_result(32'h7F800000, 1'b1, "FSUB: MAX - (-MAX) = +Inf (overflow)");

        i_data_a = 32'h7F7FFFFF; i_data_b = 32'hBF800000; #10;
        verify_result(32'h7F800000, 1'b1, "FSUB: MAX_FINITE - (-1.0) = +Inf");

        // Special values
        i_data_a = 32'h7F800000; i_data_b = 32'h3F800000; #10;
        $display("[INFO] FSUB: +Inf - 1.0 = %h", o_fp);

        i_data_a = 32'h7FC00000; i_data_b = 32'h3F800000; #10;
        $display("[INFO] FSUB: NaN - 1.0 = %h", o_fp);

        // ========================================
        // FMUL Tests (i_inst = 5'b01011)
        // ========================================
        $display("\n--- Testing FMUL ---");
        i_inst = 5'b01011;

        // Basic arithmetic
        i_data_a = 32'h40000000; i_data_b = 32'h40400000; #10;
        verify_result(32'h40C00000, 1'b0, "FMUL: 2.0 * 3.0 = 6.0");

        i_data_a = 32'h3F800000; i_data_b = 32'h3F800000; #10;
        verify_result(32'h3F800000, 1'b0, "FMUL: 1.0 * 1.0 = 1.0");

        i_data_a = 32'h40000000; i_data_b = 32'h00000000; #10;
        verify_result(32'h00000000, 1'b0, "FMUL: 2.0 * 0.0 = 0.0");

        i_data_a = 32'h40000000; i_data_b = 32'h3F800000; #10;
        verify_result(32'h40000000, 1'b0, "FMUL: 2.0 * 1.0 = 2.0");

        // Sign combinations
        i_data_a = 32'hC0000000; i_data_b = 32'h40400000; #10;
        verify_result(32'hC0C00000, 1'b0, "FMUL: -2.0 * 3.0 = -6.0");

        i_data_a = 32'hC0000000; i_data_b = 32'hC0400000; #10;
        verify_result(32'h40C00000, 1'b0, "FMUL: -2.0 * -3.0 = 6.0");

        i_data_a = 32'h40000000; i_data_b = 32'hC0400000; #10;
        verify_result(32'hC0C00000, 1'b0, "FMUL: 2.0 * -3.0 = -6.0");

        // Rounding tests (mantissa overflow)
        i_data_a = 32'h3F7FFFFF; i_data_b = 32'h3F7FFFFF; #10;
        $display("[INFO] FMUL: 0.999999 * 0.999999 = %h", o_fp);

        i_data_a = 32'h3F800001; i_data_b = 32'h3F800001; #10;
        $display("[INFO] FMUL: 1.0000001 * 1.0000001 = %h", o_fp);

        // Small numbers
        i_data_a = 32'h3F000000; i_data_b = 32'h3F000000; #10;
        verify_result(32'h3E800000, 1'b0, "FMUL: 0.5 * 0.5 = 0.25");

        i_data_a = 32'h3E800000; i_data_b = 32'h3E800000; #10;
        verify_result(32'h3D800000, 1'b0, "FMUL: 0.25 * 0.25 = 0.0625");

        // Overflow
        i_data_a = 32'h7F000000; i_data_b = 32'h7F000000; #10;
        verify_result(32'h7F800000, 1'b1, "FMUL: LARGE * LARGE = +Inf");

        i_data_a = 32'h7F7FFFFF; i_data_b = 32'h40000000; #10;
        verify_result(32'h7F800000, 1'b1, "FMUL: MAX_FINITE * 2.0 = +Inf");

        // Underflow
        i_data_a = 32'h00800000; i_data_b = 32'h00800000; #10;
        verify_result(32'h00000000, 1'b1, "FMUL: MIN_NORMAL * MIN_NORMAL = 0");

        i_data_a = 32'h00800000; i_data_b = 32'h3F000000; #10;
        $display("[INFO] FMUL: MIN_NORMAL * 0.5 = %h (subnormal)", o_fp);

        // Special values
        i_data_a = 32'h7F800000; i_data_b = 32'h40000000; #10;
        $display("[INFO] FMUL: +Inf * 2.0 = %h", o_fp);

        i_data_a = 32'h7F800000; i_data_b = 32'h00000000; #10;
        $display("[INFO] FMUL: +Inf * 0.0 = %h (NaN expected)", o_fp);

        // ========================================
        // FCVT.W.S Tests (i_inst = 5'b01100)
        // ========================================
        $display("\n--- Testing FCVT.W.S ---");
        i_inst = 5'b01100;

        // Basic conversions
        i_data_a = 32'h00000000; #10;
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: 0.0 -> 0");

        i_data_a = 32'h3F800000; #10;
        verify_result(32'h00000001, 1'b0, "FCVT.W.S: 1.0 -> 1");

        i_data_a = 32'hBF800000; #10;
        verify_result(32'hFFFFFFFF, 1'b0, "FCVT.W.S: -1.0 -> -1");

        i_data_a = 32'h42280000; #10;
        verify_result(32'h0000002A, 1'b0, "FCVT.W.S: 42.0 -> 42");

        i_data_a = 32'hC2280000; #10;
        verify_result(32'hFFFFFFD6, 1'b0, "FCVT.W.S: -42.0 -> -42");

        // Powers of 2
        i_data_a = 32'h40000000; #10;
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 2.0 -> 2");

        i_data_a = 32'h41000000; #10;
        verify_result(32'h00000008, 1'b0, "FCVT.W.S: 8.0 -> 8");

        i_data_a = 32'h43800000; #10;
        verify_result(32'h00000100, 1'b0, "FCVT.W.S: 256.0 -> 256");

        i_data_a = 32'h47800000; #10;
        verify_result(32'h00010000, 1'b0, "FCVT.W.S: 65536.0 -> 65536");

        // Rounding: Round to nearest even
        i_data_a = 32'h3F000000; #10;
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: 0.5 -> 0 (round to even)");

        i_data_a = 32'h3FC00000; #10;
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 1.5 -> 2 (round to even)");

        i_data_a = 32'h40200000; #10;
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 2.5 -> 2 (round to even)");

        i_data_a = 32'h40600000; #10;
        verify_result(32'h00000004, 1'b0, "FCVT.W.S: 3.5 -> 4 (round to even)");

        i_data_a = 32'h40900000; #10;
        verify_result(32'h00000004, 1'b0, "FCVT.W.S: 4.5 -> 4 (round to even)");

        i_data_a = 32'h40B00000; #10;
        verify_result(32'h00000006, 1'b0, "FCVT.W.S: 5.5 -> 6 (round to even)");

        // Fractional rounding
        i_data_a = 32'h3F8CCCCD; #10; // 1.1
        verify_result(32'h00000001, 1'b0, "FCVT.W.S: 1.1 -> 1");

        i_data_a = 32'h40066666; #10; // 2.1
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 2.1 -> 2");

        i_data_a = 32'h3FE66666; #10; // 1.8
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 1.8 -> 2");

        i_data_a = 32'h4015C28F; #10; // 2.34
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 2.34 -> 2");

        i_data_a = 32'h40266666; #10; // 2.6
        verify_result(32'h00000003, 1'b0, "FCVT.W.S: 2.6 -> 3");

        // Negative rounding
        i_data_a = 32'hBF000000; #10;
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: -0.5 -> 0 (round to even)");

        i_data_a = 32'hBFC00000; #10;
        verify_result(32'hFFFFFFFE, 1'b0, "FCVT.W.S: -1.5 -> -2 (round to even)");

        i_data_a = 32'hC0200000; #10;
        verify_result(32'hFFFFFFFE, 1'b0, "FCVT.W.S: -2.5 -> -2 (round to even)");

        i_data_a = 32'hBF8CCCCD; #10;
        verify_result(32'hFFFFFFFF, 1'b0, "FCVT.W.S: -1.1 -> -1");

        i_data_a = 32'hBFE66666; #10;
        verify_result(32'hFFFFFFFE, 1'b0, "FCVT.W.S: -1.8 -> -2");

        // Large values
        i_data_a = 32'h4B7FFFFF; #10; // 16777215
        verify_result(32'h00FFFFFF, 1'b0, "FCVT.W.S: 16777215.0 -> 16777215");

        i_data_a = 32'h4CFFFFFF; #10; // Large but within range
        $display("[INFO] FCVT.W.S: Large value = %h", o_fp);

        // Boundary cases
        i_data_a = 32'h4EFFFFFF; #10; // Close to 2^31-1
        $display("[INFO] FCVT.W.S: Near MAX_INT = %h", o_fp);

        i_data_a = 32'h4F000000; #10; // 2^31
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: 2^31 -> MAX_INT (overflow)");

        i_data_a = 32'hCF000000; #10; // -2^31
        verify_result(32'h80000000, 1'b0, "FCVT.W.S: -2^31 -> MIN_INT");

        i_data_a = 32'hCF000001; #10; // Slightly less than -2^31
        verify_result(32'h80000000, 1'b1, "FCVT.W.S: < -2^31 -> MIN_INT (overflow)");

        // Special values
        i_data_a = 32'h7F800000; #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: +Inf -> MAX_INT");

        i_data_a = 32'hFF800000; #10;
        verify_result(32'h80000000, 1'b1, "FCVT.W.S: -Inf -> MIN_INT");

        i_data_a = 32'h7FC00000; #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: qNaN -> MAX_INT");

        i_data_a = 32'h7F800001; #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: sNaN -> MAX_INT");

        // Very small values
        i_data_a = 32'h3F7FFFFF; #10; // 0.99999...
        verify_result(32'h00000001, 1'b0, "FCVT.W.S: 0.99999 -> 1");

        i_data_a = 32'h3F000001; #10; // Slightly > 0.5
        verify_result(32'h00000001, 1'b0, "FCVT.W.S: 0.5+ -> 1");

        i_data_a = 32'h3EFFFFFF; #10; // Slightly < 0.5
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: 0.5- -> 0");

        // ========================================
        // FCLASS Tests (i_inst = 5'b01111)
        // ========================================
        $display("\n--- Testing FCLASS ---");
        i_inst = 5'b01111;

        i_data_a = 32'hFF800000; #10;
        verify_result(32'h00000001, 1'b0, "FCLASS: -Inf -> 0x1");

        i_data_a = 32'hC0000000; #10;
        verify_result(32'h00000002, 1'b0, "FCLASS: -2.0 (Normal) -> 0x2");

        i_data_a = 32'h80000001; #10;
        verify_result(32'h00000004, 1'b0, "FCLASS: -Subnormal -> 0x4");

        i_data_a = 32'h80000000; #10;
        verify_result(32'h00000008, 1'b0, "FCLASS: -Zero -> 0x8");

        i_data_a = 32'h00000000; #10;
        verify_result(32'h00000010, 1'b0, "FCLASS: +Zero -> 0x10");

        i_data_a = 32'h00000001; #10;
        verify_result(32'h00000020, 1'b0, "FCLASS: +Subnormal -> 0x20");

        i_data_a = 32'h40000000; #10;
        verify_result(32'h00000040, 1'b0, "FCLASS: +2.0 (Normal) -> 0x40");

        i_data_a = 32'h7F800000; #10;
        verify_result(32'h00000080, 1'b0, "FCLASS: +Inf -> 0x80");

        i_data_a = 32'h7F800001; #10;
        verify_result(32'h00000100, 1'b0, "FCLASS: sNaN -> 0x100");

        i_data_a = 32'h7FC00000; #10;
        verify_result(32'h00000200, 1'b0, "FCLASS: qNaN -> 0x200");

        // Additional edge cases
        i_data_a = 32'h007FFFFF; #10; // Max subnormal
        verify_result(32'h00000020, 1'b0, "FCLASS: Max +Subnormal -> 0x20");

        i_data_a = 32'h807FFFFF; #10; // Max negative subnormal
        verify_result(32'h00000004, 1'b0, "FCLASS: Max -Subnormal -> 0x4");

        i_data_a = 32'h00800000; #10; // Min normal
        verify_result(32'h00000040, 1'b0, "FCLASS: Min +Normal -> 0x40");

        i_data_a = 32'h7F7FFFFF; #10; // Max finite
        verify_result(32'h00000040, 1'b0, "FCLASS: Max +Normal -> 0x40");

        // ========================================
        // Summary
        // ========================================
        #100;
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("Pass Rate:   %.2f%%", (pass_count * 100.0) / test_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***\n");
        else
            $display("*** %0d TESTS FAILED ***\n", fail_count);

        $finish;
    end

    // Waveform dump
    initial begin
        $fsdbDumpfile("fp_alu_tb.fsdb");
        $fsdbDumpvars(0, fp_alu_tb, "+mda");
    end

endmodule
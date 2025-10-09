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
    fp_alu dut (
        .i_data_a(i_data_a),
        .i_data_b(i_data_b),
        .i_inst(i_inst),
        .o_fp(o_fp),
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

    // Helper function to display FP number
    task display_fp;
        input [31:0] fp;
        begin
            $display("  Sign=%b, Exp=%h (%d), Mant=%h", 
                     fp[31], fp[30:23], fp[30:23], fp[22:0]);
        end
    endtask

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
        $display("FP ALU Testbench Starting");
        $display("========================================\n");

        // ========================================
        // FSUB Tests (i_inst = 5'b01010)
        // ========================================
        $display("\n--- Testing FSUB ---");
        i_inst = 5'b01010;

        // Test 1: Simple subtraction 5.0 - 3.0 = 2.0
        i_data_a = 32'h40A00000; // 5.0
        i_data_b = 32'h40400000; // 3.0
        #10;
        verify_result(32'h40000000, 1'b0, "FSUB: 5.0 - 3.0 = 2.0");

        // Test 2: Subtraction resulting in zero: 3.0 - 3.0 = 0.0
        i_data_a = 32'h40400000; // 3.0
        i_data_b = 32'h40400000; // 3.0
        #10;
        verify_result(32'h00000000, 1'b0, "FSUB: 3.0 - 3.0 = 0.0");

        // Test 3: Negative result: 2.0 - 5.0 = -3.0
        i_data_a = 32'h40000000; // 2.0
        i_data_b = 32'h40A00000; // 5.0
        #10;
        verify_result(32'hC0400000, 1'b0, "FSUB: 2.0 - 5.0 = -3.0");

        // Test 4: Small difference
        i_data_a = 32'h3F800001; // ~1.0000001
        i_data_b = 32'h3F800000; // 1.0
        #10;
        verify_result(32'h34000000, 1'b0, "FSUB: ~1.0000001 - 1.0 = ~0.0000001");
        $display("[INFO] FSUB: Small difference test - Result: %h", o_fp);

        // Test 5: Overflow case (large - (-large))
        i_data_a = 32'h7F000000; // Large positive
        i_data_b = 32'hFF000000; // Large negative
        #10;
        verify_result(32'h7F800000, 1'b1, "FSUB: Overflow to +Inf");

        // ========================================
        // FMUL Tests (i_inst = 5'b01011)
        // ========================================
        $display("\n--- Testing FMUL ---");
        i_inst = 5'b01011;

        // Test 6: Simple multiplication 2.0 * 3.0 = 6.0
        i_data_a = 32'h40000000; // 2.0
        i_data_b = 32'h40400000; // 3.0
        #10;
        verify_result(32'h40C00000, 1'b0, "FMUL: 2.0 * 3.0 = 6.0");

        // Test 7: Multiply by zero
        i_data_a = 32'h40000000; // 2.0
        i_data_b = 32'h00000000; // 0.0
        #10;
        verify_result(32'h00000000, 1'b0, "FMUL: 2.0 * 0.0 = 0.0");

        // Test 8: Multiply by one
        i_data_a = 32'h40000000; // 2.0
        i_data_b = 32'h3F800000; // 1.0
        #10;
        verify_result(32'h40000000, 1'b0, "FMUL: 2.0 * 1.0 = 2.0");

        // Test 9: Negative multiplication
        i_data_a = 32'hC0000000; // -2.0
        i_data_b = 32'h40400000; // 3.0
        #10;
        verify_result(32'hC0C00000, 1'b0, "FMUL: -2.0 * 3.0 = -6.0");

        // Test 10: Overflow
        i_data_a = 32'h7F000000; // Large
        i_data_b = 32'h7F000000; // Large
        #10;
        verify_result(32'h7F800000, 1'b1, "FMUL: Overflow to +Inf");

        // Test 11: Underflow
        i_data_a = 32'h00800000; // Min normal
        i_data_b = 32'h00800000; // Min normal
        #10;
        verify_result(32'h00000000, 1'b1, "FMUL: Underflow to 0");

        // ========================================
        // FCVT.W.S Tests (i_inst = 5'b01100)
        // ========================================
        $display("\n--- Testing FCVT.W.S ---");
        i_inst = 5'b01100;

        // Test 12: Convert 0.0
        i_data_a = 32'h00000000; // 0.0
        #10;
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: 0.0 -> 0");

        // Test 13: Convert 1.0
        i_data_a = 32'h3F800000; // 1.0
        #10;
        verify_result(32'h00000001, 1'b0, "FCVT.W.S: 1.0 -> 1");

        // Test 14: Convert -1.0
        i_data_a = 32'hBF800000; // -1.0
        #10;
        verify_result(32'hFFFFFFFF, 1'b0, "FCVT.W.S: -1.0 -> -1");

        // Test 15: Convert 42.0
        i_data_a = 32'h42280000; // 42.0
        #10;
        verify_result(32'h0000002A, 1'b0, "FCVT.W.S: 42.0 -> 42");

        // Test 16: Convert -42.0
        i_data_a = 32'hC2280000; // -42.0
        #10;
        verify_result(32'hFFFFFFD6, 1'b0, "FCVT.W.S: -42.0 -> -42");

        // Test 17: Convert 0.5 (rounds to 0)
        i_data_a = 32'h3F000000; // 0.5
        #10;
        verify_result(32'h00000000, 1'b0, "FCVT.W.S: 0.5 -> 0");

        // Test 18: Convert 1.5 (rounds to 2, nearest even)
        i_data_a = 32'h3FC00000; // 1.5
        #10;
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 1.5 -> 2");

        // Test 19: Convert 2.5 (rounds to 2, nearest even)
        i_data_a = 32'h40200000; // 2.5
        #10;
        verify_result(32'h00000002, 1'b0, "FCVT.W.S: 2.5 -> 2");

        // Test 20: Convert +Inf
        i_data_a = 32'h7F800000; // +Inf
        #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: +Inf -> MAX_INT");

        // Test 21: Convert -Inf
        i_data_a = 32'hFF800000; // -Inf
        #10;
        verify_result(32'h80000000, 1'b1, "FCVT.W.S: -Inf -> MIN_INT");

        // Test 22: Convert NaN
        i_data_a = 32'h7FC00000; // NaN
        #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: NaN -> MAX_INT");

        // Test 23: Convert large positive (overflow)
        i_data_a = 32'h4F800000; // 2^32
        #10;
        verify_result(32'h7FFFFFFF, 1'b1, "FCVT.W.S: Overflow -> MAX_INT");

        // Test 24: Convert large negative (overflow)
        i_data_a = 32'hCF800000; // -2^32
        #10;
        verify_result(32'h80000000, 1'b1, "FCVT.W.S: Negative overflow -> MIN_INT");

        // Test 25: Convert max representable int (2^31-1 ~ 2147483647)
        i_data_a = 32'h4EFFFFFF; // ~2^31-1
        #10;
        $display("[INFO] FCVT.W.S: Max int conversion - Result: %h", o_fp);

        // ========================================
        // FCLASS Tests (i_inst = 5'b01111)
        // ========================================
        $display("\n--- Testing FCLASS ---");
        i_inst = 5'b01111;

        // Test 26: Classify -Inf
        i_data_a = 32'hFF800000; // -Inf
        #10;
        verify_result(32'h00000001, 1'b0, "FCLASS: -Inf -> 0x1");

        // Test 27: Classify -Normal
        i_data_a = 32'hC0000000; // -2.0
        #10;
        verify_result(32'h00000002, 1'b0, "FCLASS: -Normal -> 0x2");

        // Test 28: Classify -Subnormal
        i_data_a = 32'h80000001; // -Subnormal
        #10;
        verify_result(32'h00000004, 1'b0, "FCLASS: -Subnormal -> 0x4");

        // Test 29: Classify -Zero
        i_data_a = 32'h80000000; // -0
        #10;
        verify_result(32'h00000008, 1'b0, "FCLASS: -Zero -> 0x8");

        // Test 30: Classify +Zero
        i_data_a = 32'h00000000; // +0
        #10;
        verify_result(32'h00000010, 1'b0, "FCLASS: +Zero -> 0x10");

        // Test 31: Classify +Subnormal
        i_data_a = 32'h00000001; // +Subnormal
        #10;
        verify_result(32'h00000020, 1'b0, "FCLASS: +Subnormal -> 0x20");

        // Test 32: Classify +Normal
        i_data_a = 32'h40000000; // 2.0
        #10;
        verify_result(32'h00000040, 1'b0, "FCLASS: +Normal -> 0x40");

        // Test 33: Classify +Inf
        i_data_a = 32'h7F800000; // +Inf
        #10;
        verify_result(32'h00000080, 1'b0, "FCLASS: +Inf -> 0x80");

        // Test 34: Classify Signaling NaN
        i_data_a = 32'h7F800001; // sNaN
        #10;
        verify_result(32'h00000100, 1'b0, "FCLASS: sNaN -> 0x100");

        // Test 35: Classify Quiet NaN
        i_data_a = 32'h7FC00000; // qNaN
        #10;
        verify_result(32'h00000200, 1'b0, "FCLASS: qNaN -> 0x200");

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
        $display("========================================\n");

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***\n");
        else
            $display("*** SOME TESTS FAILED ***\n");

        $finish;
    end

    // Waveform dump
    initial begin
        $fsdbDumpfile("fp_alu_tb.fsdb");
        $fsdbDumpvars(0, fp_alu_tb, "+mda");
    end

endmodule
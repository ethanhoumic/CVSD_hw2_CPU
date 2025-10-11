`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000

`ifdef p0
    `define Inst   "../00_TB/PATTERN/p0/inst.dat"
    `define Data   "../00_TB/PATTERN/p0/data.dat"
    `define Status "../00_TB/PATTERN/p0/status.dat"
`elsif p1
    `define Inst   "../00_TB/PATTERN/p1/inst.dat"
    `define Data   "../00_TB/PATTERN/p1/data.dat"
    `define Status "../00_TB/PATTERN/p1/status.dat"
`elsif p2
    `define Inst   "../00_TB/PATTERN/p2/inst.dat"
    `define Data   "../00_TB/PATTERN/p2/data.dat"
    `define Status "../00_TB/PATTERN/p2/status.dat"
`elsif p3
    `define Inst   "../00_TB/PATTERN/p3/inst.dat"
    `define Data   "../00_TB/PATTERN/p3/data.dat"
    `define Status "../00_TB/PATTERN/p3/status.dat"
`else
    `define Inst   "../00_TB/PATTERN/p0/inst.dat"
    `define Data   "../00_TB/PATTERN/p0/data.dat"
    `define Status "../00_TB/PATTERN/p0/status.dat"
`endif

module testbed;

    reg  rst_n;
    reg  clk = 0;
    wire            dmem_we;
    wire [ 31 : 0 ] dmem_addr;
    wire [ 31 : 0 ] dmem_wdata;
    wire [ 31 : 0 ] dmem_rdata;
    wire [  2 : 0 ] o_status;
    wire            o_status_valid;

    integer cycle_count;
    integer status_count;
    integer error_count;
    integer i;
    integer status_length;
    
    reg [2:0] golden_status [0:1023];
    reg [31:0] golden_data [0:2047];
    reg simulation_done;

    core u_core (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .o_status(o_status),
        .o_status_valid(o_status_valid),
        .o_we(dmem_we),
        .o_addr(dmem_addr),
        .o_wdata(dmem_wdata),
        .i_rdata(dmem_rdata)
    );

    data_mem u_data_mem (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_we(dmem_we),
        .i_addr(dmem_addr),
        .i_wdata(dmem_wdata),
        .o_rdata(dmem_rdata)
    );

    // Clock generation
    always #(`HCYCLE) clk = ~clk;

    // Load data memory and golden data
    initial begin 
        rst_n = 1;
        simulation_done = 0;
        #(0.25 * `CYCLE) rst_n = 0;
        #(`CYCLE) rst_n = 1;
        
        // Load instruction memory
        $readmemb(`Inst, u_data_mem.mem_r);
        
        // Load golden data
        $readmemb(`Data, golden_data);
        
        // Load golden status and count how many entries
        // Initialize all entries to X first
        for (i = 0; i < 1024; i = i + 1) begin
            golden_status[i] = 3'bxxx;
        end
        
        $readmemb(`Status, golden_status);
        
        // Count valid status entries (stop at first X or at known end patterns)
        status_length = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            if (golden_status[i] === 3'bxxx) begin
                status_length = i;
                i = 1024; // break
            end
            // Also stop if we see EOF or INVALID
            else if (golden_status[i] == 3'd6 || golden_status[i] == 3'd5) begin
                status_length = i + 1;
                i = 1024; // break
            end
        end
        
        cycle_count = 0;
        status_count = 0;
        error_count = 0;
        
        $display("========================================");
        $display("  Simulation Start");
        $display("  Expected status count: %d", status_length);
        $display("========================================");
    end

    // Cycle counter and timeout check
    always @(posedge clk) begin
        if (rst_n && !simulation_done) begin
            cycle_count = cycle_count + 1;
            
            if (cycle_count >= `MAX_CYCLE) begin
                $display("========================================");
                $display("  FAIL: Timeout after %d cycles", `MAX_CYCLE);
                $display("  Processed %d/%d statuses", status_count, status_length);
                $display("========================================");
                simulation_done = 1;
                #(`CYCLE);
                $finish;
            end
        end
    end

    // Status checking (at negative edge as specified in homework)
    always @(negedge clk) begin
        if (rst_n && o_status_valid && !simulation_done) begin
            // Check if we're reading beyond expected status count
            if (status_count >= status_length) begin
                $display("ERROR at cycle %d: Unexpected extra status output!", cycle_count);
                $display("  Already processed %d statuses, but got another: %d", status_length, o_status);
                error_count = error_count + 1;
				$finish;
            end
            else if (golden_status[status_count] === 3'bxxx) begin
                $display("ERROR at cycle %d: No golden status available!", cycle_count);
                $display("  Status index: %d, Got: %d", status_count, o_status);
                error_count = error_count + 1;
            end
            else if (o_status !== golden_status[status_count]) begin
                $display("ERROR at cycle %d: Status mismatch!", cycle_count);
                $display("  Status index: %d", status_count);
                $display("  Expected: %d, Got: %d", golden_status[status_count], o_status);
                error_count = error_count + 1;
            end
            else begin
                $display("Status %d correct: %d at cycle %d", status_count, o_status, cycle_count);
            end
            
            status_count = status_count + 1;
            
            // Stop immediately when EOF status (6) is detected
            if (o_status == 3'd6) begin
                simulation_done = 1;
                $display("========================================");
                $display("  EOF detected at cycle %d", cycle_count);
                $display("========================================");
                
                // Wait one more cycle then check memory and finish
                @(posedge clk);
                #1;
                check_memory();
                finish_simulation();
            end
            // Also stop for INVALID_TYPE (5)
            else if (o_status == 3'd5) begin
                simulation_done = 1;
                $display("========================================");
                $display("  INVALID_TYPE detected at cycle %d", cycle_count);
                $display("========================================");
                
                // Wait one more cycle then check memory and finish
                @(posedge clk);
                #1;
                check_memory();
                finish_simulation();
            end
        end
    end

    // Task to check memory data against golden data
    task check_memory;
        integer mem_error;
        integer first_nonzero;
        integer last_nonzero;
        begin
            mem_error = 0;
            first_nonzero = -1;
            last_nonzero = -1;
            
            // Find range of non-zero golden data
            for (i = 1024; i < 2048; i = i + 1) begin
                if (golden_data[i] !== 32'h0 && golden_data[i] !== 32'hxxxxxxxx) begin
                    if (first_nonzero == -1) first_nonzero = i;
                    last_nonzero = i;
                end
            end
            
            $display("========================================");
            $display("  Checking Memory Data");
            if (first_nonzero != -1) begin
                $display("  Golden data range: [%d:%d]", first_nonzero, last_nonzero);
            end
            else begin
                $display("  No golden data to check (all zeros/X)");
            end
            $display("========================================");
            
            // Check data memory - only check range with golden data
            if (first_nonzero != -1) begin
                for (i = first_nonzero; i <= last_nonzero; i = i + 1) begin
                    if (golden_data[i] !== 32'hxxxxxxxx) begin
                        if (u_data_mem.mem_r[i] !== golden_data[i]) begin
                            $display("ERROR: Memory[%d] mismatch!", i);
                            $display("  Address: %h", i * 4);
                            $display("  Expected: %h, Got: %h", golden_data[i], u_data_mem.mem_r[i]);
                            mem_error = mem_error + 1;
                            error_count = error_count + 1;
                            
                            // Limit error messages
                            if (mem_error >= 10) begin
                                $display("  ... (stopping after 10 memory errors)");
                                i = 2048; // break
                            end
                        end
                    end
                end
            end
            
            if (mem_error == 0) begin
                $display("Memory check PASSED!");
            end
            else begin
                $display("Memory check FAILED with %d errors!", mem_error);
            end
        end
    endtask

    // Task to finish simulation
    task finish_simulation;
        begin
            $display("========================================");
            if (error_count == 0) begin
                $display("  Simulation PASSED!");
                $display("  *** CONGRATULATIONS! ***");
            end
            else begin
                $display("  Simulation FAILED with %d errors!", error_count);
            end
            $display("  Total cycles: %d", cycle_count);
            $display("  Total statuses: %d", status_count);
            $display("========================================");
            
            #(`CYCLE * 2);
            $finish;
        end
    endtask

    // Waveform dump
    initial begin
        $fsdbDumpfile("core.fsdb");
        $fsdbDumpvars(0, testbed, "+mda");
    end

endmodule
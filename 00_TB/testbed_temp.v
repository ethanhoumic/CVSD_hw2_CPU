`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000

`ifdef p0
    `define Inst "../00_TB/PATTERN/p0/inst.dat"
`elsif p1
    `define Inst "../00_TB/PATTERN/p1/inst.dat"
`elsif p2
	`define Inst "../00_TB/PATTERN/p2/inst.dat"
`elsif p3
	`define Inst "../00_TB/PATTERN/p3/inst.dat"
`else
	`define Inst "../00_TB/PATTERN/p0/inst.dat"
`endif

module testbed;

	reg  rst_n;
	reg  clk = 0;
	wire            dmem_we;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  1 : 0 ] mips_status;
	wire            mips_status_valid;

	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_status(),
		.o_status_valid(),
		.o_we(),
		.o_addr(),
		.o_wdata(),
		.i_rdata()
	);

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_we(),
		.i_addr(),
		.i_wdata(),
		.o_rdata()
	);

	always #(`HCYCLE) clk = ~clk;

	// load data memory
	initial begin 
		rst_n = 1;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		$readmemb (`Inst, u_data_mem.mem_r);
	end

endmodule
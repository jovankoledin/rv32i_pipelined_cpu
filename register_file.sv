`ifndef _register_file_v
`define _register_file_v

module register_file (
    input  logic        clk,            // Clock signal
    input  logic        reset,          // Reset signal (synchronous)
    input  logic        reg_write,      // Register write enable
    input  logic [4:0]  rs1,            // Source register 1 address
    input  logic [4:0]  rs2,            // Source register 2 address
    input  logic [4:0]  rd,             // Destination register address
    input  logic [31:0] write_data,     // Data to write into the destination register
    output logic [31:0] read_data1,     // Data read from source register 1
    output logic [31:0] read_data2      // Data read from source register 2
);

    // Register file storage (32 registers, 32 bits each)
    logic [31:0] reg_file [0:31];

    // Synchronous reset and write logic
    always @(posedge clk) begin
        if (reset) begin
            // Reset all registers to 0
            integer i;
            for (i = 0; i < 32; i = i + 1) begin
                reg_file[i] <= 32'b0;
            end
        end else if (reg_write && rd != 5'b0) begin
            // Write data to the destination register (ignore writes to x0)
            reg_file[rd] <= write_data;
        end
    end

    // Combinational read logic
    always_comb begin
        // Read source registers
        read_data1 = (rs1 != 5'b0) ? reg_file[rs1] : 32'b0; // x0 always reads 0
        read_data2 = (rs2 != 5'b0) ? reg_file[rs2] : 32'b0; // x0 always reads 0
    end

endmodule

`endif

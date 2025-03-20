// alu.v
`ifndef _ALU_V
`define _ALU_V

module alu(
    input logic [31:0] src1,
    input logic [31:0] src2,
    input logic [3:0] alu_ctrl,
    output logic [31:0] alu_result
);

    logic [4:0] shift_amount;
    assign shift_amount = src2[4:0];  // Use lower 5 bits for shift operations

    always_comb begin
        case (alu_ctrl)
            4'b0000: alu_result = src1 + src2;                 // ADD
            4'b0001: alu_result = src1 - src2;                 // SUB
            4'b0010: alu_result = src1 << shift_amount;        // SLL
            4'b0011: alu_result = src1 >> shift_amount;        // SRL
            4'b0100: alu_result = $signed(src1) >>> shift_amount; // SRA
            4'b0101: alu_result = src1 ^ src2;                  // XOR
            4'b0110: alu_result = src1 | src2;                  // OR
            4'b0111: alu_result = src1 & src2;                  // AND
            4'b1000: alu_result = ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0; // SLT
            4'b1001: alu_result = src1 << shift_amount;           // SLLI
            4'b1010: alu_result = src1 >> shift_amount;           // SRLI
            4'b1100: alu_result = (src1 < src2) ? 32'd1 : 32'd0;     // SLTIU (unsigned)
            4'b1011: alu_result = $signed(src1) >>> shift_amount; // SRAI
            4'b1111: alu_result = src2;  // Bypass src2 (immediate) directly
            default: alu_result = 32'b0;                       // Default
        endcase
    end

endmodule
`endif

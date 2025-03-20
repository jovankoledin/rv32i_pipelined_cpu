`ifndef _CORE_PIPELINED_V_
`define _CORE_PIPELINED_V_

`include "system.sv"
`include "base.sv"
`include "memory_io.sv"
`include "memory.sv"
`include "register_file.sv"
`include "alu.sv"
`include "instruction_to_english.sv"

module core (
    input  logic                          clk,
    input  logic                          reset,
    input  logic [`word_address_size-1:0] reset_pc,
    output memory_io_req                  inst_mem_req,
    input  memory_io_rsp                  inst_mem_rsp,
    output memory_io_req                  data_mem_req,
    input  memory_io_rsp                  data_mem_rsp
);

    //--------------------------------------------------------------------------
    // IF Stage: Instruction Fetch
    //--------------------------------------------------------------------------

    // Program Counter update (for simplicity, no branch logic is used here)
    logic [31:0] pc, ctr;
    logic branch_taken, branch_taken_reg, ex_branch_mispredicted;
    logic [4:0]  id_rs1, id_rs2, id_rd;

    // Send request to instruction memory
    assign inst_mem_req.addr    = pc;
    assign inst_mem_req.do_read = 4'b1111; // full word read
    assign inst_mem_req.valid   = 1'b1;

    // IF/ID Pipeline registers
    logic [31:0] if_id_pc;
    logic [31:0] if_id_instruction;
    logic stall_pipeline;
    logic flush_if_id;

    // Update IF/ID pipeline register with proper flush control
    always_ff @(posedge clk) begin
        if (reset) begin
            ctr <= 32'b0;
            if_id_pc          <= 32'b0;
            if_id_instruction <= 32'b0;
        end 
        else if (stall_pipeline) begin
            // On hazard stall, retain previous IF/ID register values
            if_id_pc          <= if_id_pc;
            if_id_instruction <= if_id_instruction;
        end 
        else if (flush_if_id || ex_branch_mispredicted) begin
            // Flush pipeline on branch misprediction: insert a NOP
            if_id_pc          <= pc;
            if_id_instruction <= 32'h00000013;  // NOP (ADDI x0, x0, 0)
        end 
        else begin
            // Normal operation: update IF/ID registers
            if_id_pc          <= pc;
            if (inst_mem_rsp.valid) begin
                if_id_instruction <= inst_mem_rsp.data;
                print_instruction(if_id_pc, if_id_instruction);
            end else begin
                if_id_instruction <= if_id_instruction;
            end
        end
    end


    //--------------------------------------------------------------------------
    // ID Stage: Instruction Decode and Register File Read
    //--------------------------------------------------------------------------

    // Decode common instruction fields
    logic [2:0]  id_funct3;
    logic [6:0]  id_opcode, id_funct7;
    assign id_rs1    = if_id_instruction[19:15];
    assign id_rs2    = if_id_instruction[24:20];
    assign id_rd     = if_id_instruction[11:7];
    assign id_funct3 = if_id_instruction[14:12];
    assign id_funct7 = if_id_instruction[31:25];
    assign id_opcode = if_id_instruction[6:0];

    // Immediate extraction
    logic [31:0] id_imm;
    always_comb begin
        case (id_opcode)
            7'b1100011: // B-type
                id_imm = $signed({if_id_instruction[31], if_id_instruction[7],
                                    if_id_instruction[30:25], if_id_instruction[11:8],
                                    1'b0});
            7'b1101111: // J-type
                id_imm = $signed({if_id_instruction[31], if_id_instruction[19:12],
                                    if_id_instruction[20], if_id_instruction[30:21],
                                    1'b0});
            7'b0100011: // S-type (store)
                id_imm = $signed({if_id_instruction[31:25], if_id_instruction[11:7]});
            7'b0000011: // Load instructions
                id_imm = $signed(if_id_instruction[31:20]);
            7'b0010011: // I-type ALU instructions
                id_imm = $signed(if_id_instruction[31:20]);
            7'b1100111: // JALR
                id_imm = $signed(if_id_instruction[31:20]);
            7'b0110111: // LUI (U-type)
                id_imm = {if_id_instruction[31:12], 12'b0};
            default:    id_imm = 32'b0;
        endcase
    end

    // In the top module declarations
    logic [1:0] branch_prediction_state; // 2-bit saturating counter
    logic [31:0] branch_history_table [63:0]; // Simple branch history table
    logic [5:0] branch_history_index; // Index into BHT
    logic [31:0] regData1, regData2, branch_target;
    logic id_ex_reg_write;
    logic [4:0] id_ex_rd, ex_mem_rd;
    // ALU instance to perform operations as per control signals
    logic [31:0] ex_alu_result, ex_mem_alu_result;
    logic ex_mem_reg_write;

    // In ID stage, use consistent calculation for branch target prediction
    always_comb begin
        // Generate index for branch history table
        branch_history_index = if_id_pc[7:2]; // Use lower bits of PC
        
        // Predict branch based on branch history table
        if (id_opcode == 7'b1101111 || id_opcode == 7'b1100111) begin
            // JAL and JALR are always taken
            branch_taken = 1'b1;
            if (id_opcode == 7'b1101111) begin
               // JAL - PC-relative offset
               branch_target = if_id_pc + id_imm;
            end else begin
               // JALR - Use forwarded value for rs1 if available for more accurate prediction
               logic [31:0] rs1_value;
               
               // Check if we need forwarding for rs1
               if (id_ex_reg_write && id_ex_rd != 0 && id_ex_rd == id_rs1)
                   rs1_value = ex_alu_result;
               else if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_rs1)
                   rs1_value = ex_mem_alu_result;
               else
                   rs1_value = regData1;
                   
               branch_target = (rs1_value + id_imm) & ~32'h1; // Clear LSB for alignment
            end
        end else if (id_opcode == 7'b1100011) begin // B-type branches
            // Use branch history table for prediction
            branch_taken = branch_history_table[branch_history_index] >= 2'b10;
            branch_target = if_id_pc + id_imm;
        end else begin
            branch_taken = 1'b0;
            branch_target = 32'b0;
        end
    end

    // Register for branch target
    logic [31:0] branch_target_reg;
    always_ff @(posedge clk) begin
    if (reset)
        branch_target_reg <= 32'b0;
    // Only update the branch target register when the branch is taken
    else if (branch_taken)
        branch_target_reg <= branch_target;
    end

    // Register branch_taken into branch_taken_reg for use in later pipeline flushes
    always_ff @(posedge clk) begin
        if (reset)
            branch_taken_reg <= 1'b0;
        else
            branch_taken_reg <= branch_taken;
    end

    // Register file instance (write-back signals come later from WB stage)
    logic        wb_reg_write;
    logic [4:0]  wb_rd;
    logic [31:0] wb_write_data;

    register_file regfile (
        .clk(clk),
        .reset(reset),
        .reg_write(wb_reg_write),
        .rs1(id_rs1),
        .rs2(id_rs2),
        .rd(wb_rd),
        .write_data(wb_write_data),
        .read_data1(regData1),
        .read_data2(regData2)
    );

    // Generate control signals based on opcode and function fields
    logic id_mem_read, id_mem_write, id_reg_write, id_alu_src, id_ex_mem_read;
    logic [6:0]  id_ex_opcode;
    logic [3:0] id_alu_control;
    always_comb begin
        // Defaults
        id_mem_read    = 1'b0;
        id_mem_write   = 1'b0;
        id_reg_write   = 1'b0;
        id_alu_src     = 1'b0;
        id_alu_control = 4'b0000;
        case (id_opcode)
            7'b0110011: begin // R-type
                id_reg_write = 1'b1;
                id_alu_src   = 1'b0;
                case (id_funct3)
                    3'b000: id_alu_control = (if_id_instruction[30] ? 4'b0001 : 4'b0000); // SUB / ADD
                    3'b001: id_alu_control = 4'b0010;  // SLL
                    3'b101: id_alu_control = (if_id_instruction[30] ? 4'b0100 : 4'b0011); // SRA / SRL
                    3'b010: id_alu_control = 4'b1000;  // SLT
                    3'b100: id_alu_control = 4'b0101;  // XOR
                    3'b110: id_alu_control = 4'b0110;  // OR
                    3'b111: id_alu_control = 4'b0111;  // AND
                    default: id_alu_control = 4'b0000;
                endcase
            end
            7'b0010011: begin // I-type ALU
                id_reg_write = 1'b1;
                id_alu_src   = 1'b1;
                case (id_funct3)
                    3'b000: id_alu_control = 4'b0000; // ADDI
                    3'b010: id_alu_control = 4'b1000; // SLTI
                    3'b011: id_alu_control = 4'b1100; // SLTIU
                    3'b001: id_alu_control = 4'b0010; // SLLI
                    3'b101: id_alu_control = (if_id_instruction[30] ? 4'b0100 : 4'b0011); // SRAI / SRLI
                    3'b100: id_alu_control = 4'b0101; // XORI
                    3'b110: id_alu_control = 4'b0110; // ORI
                    3'b111: id_alu_control = 4'b0111; // ANDI
                    default: id_alu_control = 4'b0000;
                endcase
            end
            7'b0000011: begin // Load
                id_reg_write   = 1'b1;
                id_alu_src     = 1'b1;
                id_mem_read    = 1'b1;
                id_alu_control = 4'b0000; // Use ADD for effective address computation
            end
            7'b0100011: begin // Store
                id_reg_write   = 1'b0;
                id_alu_src     = 1'b1;
                id_mem_write   = 1'b1;
                id_alu_control = 4'b0000;
            end
            7'b1101111,       // JAL
            7'b1100111: begin // JALR
                id_reg_write   = 1'b1;
                id_alu_src     = 1'b0;
                id_alu_control = 4'b0000;
            end
            7'b0110111: begin // LUI (U-type)
                id_reg_write   = 1'b1;
                id_alu_src     = 1'b1;       // Ignore ALU (no addition)
                id_alu_control = 4'b1111;    // Add a new ALU opcode for "pass immediate"
            end
            default: begin
                id_reg_write = 1'b0;
            end
        endcase
    end

    // Hazard Detection Unit Logic
    assign load_use_hazard = id_ex_mem_read && 
                        (id_ex_rd != 5'b0) && 
                        ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2));

    // Final stall signal
    logic mem_port_conflict;
    logic [31:0] ex_branch_target;
    assign stall_pipeline = load_use_hazard || mem_port_conflict;

    // Improved pipeline flush logic for handling jal, jalr, and branch mispredictions
    assign flush_if_id = ((id_ex_opcode == 7'b1101111) || (id_ex_opcode == 7'b1100111)) || ex_branch_mispredicted;
    
    // Consolidated PC update logic with clear priority
    always_ff @(posedge clk) begin
        if (reset)
            pc <= reset_pc;
        else if (branch_taken)
            pc <= branch_target;          // Speculative branch
        else if (ex_branch_mispredicted)
            pc <= ex_branch_target;       // Correct PC on branch misprediction
        else if (stall_pipeline)
            pc <= pc;                     // Hold PC on a pipeline stall
        else
            pc <= pc + 4;                 // Default increment of PC
    end

    // ID/EX Pipeline Registers: latch values for next stage
    logic [31:0] id_ex_pc, id_ex_reg_data1, id_ex_reg_data2, id_ex_imm;
    logic [2:0]  id_ex_funct3;
    logic [3:0]  id_ex_alu_control;
    logic [4:0]  id_ex_rs1, id_ex_rs2;
    logic        id_ex_alu_src, id_ex_mem_write;

    // Improved ID/EX pipeline register update with flush on branch misprediction
    always_ff @(posedge clk) begin
        if (reset || ex_branch_mispredicted) begin
            // Reset or flush condition
            id_ex_pc          <= 32'b0;
            id_ex_reg_data1   <= 32'b0;
            id_ex_reg_data2   <= 32'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_control <= 4'b0;
            id_ex_alu_src     <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_reg_write   <= 1'b0;
            id_ex_rd          <= 5'b0;
            id_ex_opcode      <= 7'b0;
            id_ex_funct3      <= 3'b0;
            id_ex_rs1         <= 5'b0;
            id_ex_rs2         <= 5'b0;
        end else if (stall_pipeline) begin
            // On stall, insert NOP by clearing control signals but preserving PC and data
            id_ex_alu_control <= 4'b0;
            id_ex_alu_src     <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_reg_write   <= 1'b0;
            id_ex_rd          <= 5'b0;
            // Keep other values unchanged
        end else begin
            // Normal operation
            id_ex_pc          <= if_id_pc;
            id_ex_reg_data1   <= regData1;
            id_ex_reg_data2   <= regData2;
            id_ex_imm         <= id_imm;
            id_ex_alu_control <= id_alu_control;
            id_ex_alu_src     <= id_alu_src;
            id_ex_mem_read    <= id_mem_read;
            id_ex_mem_write   <= id_mem_write;
            id_ex_reg_write   <= id_reg_write;
            id_ex_rd          <= id_rd;
            id_ex_funct3      <= id_funct3;
            id_ex_rs1         <= id_rs1;
            id_ex_rs2         <= id_rs2;
            id_ex_opcode      <= id_opcode;
        end
    end


    //--------------------------------------------------------------------------
    // EX Stage: Execute (ALU operations)
    //--------------------------------------------------------------------------
    // Determine the second ALU operand (immediate or register)
        // ALU input selection with forwarding
    logic [31:0] ex_mem_reg_data2, ex_mem_imm;
    logic [31:0] alu_src1, alu_src2, ex_alu_operand2;
    logic [1:0] forward_a, forward_b;

    // First operand forwarding mux
    always_comb begin
        case (forward_a)
            2'b00: alu_src1 = id_ex_reg_data1;           // No forwarding
            2'b01: alu_src1 = wb_write_data;             // Forward from WB stage
            2'b10: alu_src1 = ex_mem_alu_result;         // Forward from MEM stage
            default: alu_src1 = id_ex_reg_data1;
        endcase
    end

    // Second operand forwarding mux (before immediate selection)
    logic [31:0] forwarded_reg_data2;
    logic        mem_wb_reg_write;
    logic [4:0]  mem_wb_rd;
    
    always_comb begin
        case (forward_b)
            2'b00: forwarded_reg_data2 = id_ex_reg_data2; // No forwarding
            2'b01: forwarded_reg_data2 = wb_write_data;   // Forward from WB stage
            2'b10: forwarded_reg_data2 = ex_mem_alu_result; // Forward from MEM stage
            default: forwarded_reg_data2 = id_ex_reg_data2;
        endcase
    end

    // Consolidated forwarding logic for ALU operand A
    always_comb begin
        // Default: No forwarding
        forward_a = 2'b00;
        
        // EX/MEM forwarding
        if (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end
        // MEM/WB forwarding
        else if (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end
    end

    // Simplified forwarding logic for ALU operand B
    always_comb begin
        // Default: No forwarding
        forward_b = 2'b00;
        
        // EX/MEM forwarding
        if (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end
        // MEM/WB forwarding
        else if (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end
    end

    // Add branch resolution in EX stage
    logic ex_branch_taken;
    logic        ex_mem_mem_write;

    // Add specialized forwarding logic for branch conditions in EX stage:
    // Create dedicated forwarding for branch comparison
    logic [31:0] branch_op1, branch_op2;
     
    // Branch operand 1 forwarding logic
    always_comb begin
        // Default: Use ALU src1 (already forwarded)
        branch_op1 = alu_src1;
    end
     
    // Branch operand 2 forwarding logic with more aggressive forwarding
    always_comb begin
        // Default: Use forwarded register data 2
        branch_op2 = forwarded_reg_data2;
        
        // Special case: Check for write-back data in this cycle that's not yet visible
        if (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            branch_op2 = wb_write_data;
        end
    end

    // In EX stage, add branch resolution logic
    always_comb begin
        ex_branch_taken = 1'b0;
        ex_branch_target = 32'b0;
    
        if (id_ex_opcode == 7'b1101111) begin // JAL (unconditional)
            ex_branch_taken = 1'b1;
            ex_branch_target = id_ex_pc + id_ex_imm;
            // For unconditional jumps, don’t flag a misprediction
            ex_branch_mispredicted = 1'b0;
        end else if (id_ex_opcode == 7'b1100111) begin // JALR (unconditional)
            ex_branch_taken = 1'b1;
            ex_branch_target = (alu_src1 + id_ex_imm) & ~32'h00000001;
            // For unconditional jumps, don’t flag a misprediction
            ex_branch_mispredicted = 1'b0;
        end else if (id_ex_opcode == 7'b1100011) begin // B-type branches (conditional)
            case (id_ex_funct3)
                3'b000: ex_branch_taken = (branch_op1 == branch_op2); // BEQ
                3'b001: ex_branch_taken = (branch_op1 != branch_op2); // BNE
                3'b100: ex_branch_taken = ($signed(branch_op1) < $signed(branch_op2)); // BLT
                3'b101: ex_branch_taken = ($signed(branch_op1) >= $signed(branch_op2)); // BGE
                3'b110: ex_branch_taken = (branch_op1 < branch_op2); // BLTU
                3'b111: ex_branch_taken = (branch_op1 >= branch_op2); // BGEU
                default: ex_branch_taken = 1'b0;
            endcase
            ex_branch_target = id_ex_pc + id_ex_imm;
            // Only check misprediction for conditional branches:
            ex_branch_mispredicted = (ex_branch_taken != branch_taken_reg) ||
                (ex_branch_taken && branch_taken_reg &&
                (ex_branch_target != branch_target_reg));
        end else begin
            // For non-branch instructions, no misprediction correction is needed.
            ex_branch_mispredicted = 1'b0;
        end
    end

    // Update branch history table properly
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 64; i++)
                branch_history_table[i] <= 2'b01; // Initialize to weakly not taken
        end else if (id_ex_opcode == 7'b1100011) begin // Only update for conditional branches
            branch_history_index = id_ex_pc[7:2];
            if (ex_branch_taken) begin
                // Branch was taken, increment counter (saturating)
                branch_history_table[branch_history_index] <= 
                    (branch_history_table[branch_history_index] == 2'b11) ? 
                    2'b11 : branch_history_table[branch_history_index] + 1;
            end else begin
                // Branch was not taken, decrement counter (saturating)
                branch_history_table[branch_history_index] <= 
                    (branch_history_table[branch_history_index] == 2'b00) ? 
                    2'b00 : branch_history_table[branch_history_index] - 1;
            end
        end
    end

    // Final ALU operand 2 selection (immediate or register)
    assign ex_alu_operand2 = (id_ex_alu_src) ? id_ex_imm : forwarded_reg_data2;

    // ALU instance
    alu alu_inst (
        .src1(alu_src1),
        .src2(ex_alu_operand2),
        .alu_ctrl(id_ex_alu_control),
        .alu_result(ex_alu_result)
    );

    // Add logic to handle memory port conflicts, check if reading and writing is happening simultaneously to same data address/port
    assign mem_port_conflict = id_ex_mem_read && ex_mem_mem_write && 
                            (ex_alu_result == ex_mem_alu_result);

    // EX/MEM Pipeline Registers: Passing the ALU result and control signals
    logic        ex_mem_mem_read;
    logic [4:0]  ex_mem_alu_control;
    logic [6:0]  ex_mem_opcode;
    logic [2:0]  ex_mem_funct3;
    always_ff @(posedge clk) begin
        if (reset || ex_branch_mispredicted) begin
            ex_mem_alu_result <= 32'b0;
            ex_mem_reg_data2  <= 32'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_rd         <= 5'b0;
            ex_mem_alu_control <= 4'b0;  
            ex_mem_opcode      <= 7'b0;  
            ex_mem_imm <= 32'b0;  

        end else begin
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_reg_data2  <= id_ex_reg_data2; // For store instructions
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_funct3 <= id_ex_funct3;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_opcode <= id_ex_opcode;
            ex_mem_alu_control <= id_ex_alu_control;
            ex_mem_imm <= id_ex_imm;

        end
    end

    //--------------------------------------------------------------------------
    // MEM Stage: Memory Access
    //--------------------------------------------------------------------------

    // Memory request signals are driven combinationally based on control signals.
    always_comb begin
        // Default assignments: No memory access
        data_mem_req.valid    = 1'b0;
        data_mem_req.addr     = 32'b0;
        data_mem_req.do_read  = 4'b0000;
        data_mem_req.do_write = 4'b0000;
        data_mem_req.data     = 32'b0;
        
        if (ex_mem_mem_read) begin
            data_mem_req.valid    = 1'b1;
            data_mem_req.addr     = ex_mem_alu_result;
            data_mem_req.do_read  = 4'b1111; // Read a full 32-bit word
        end
        else if (ex_mem_mem_write) begin
            data_mem_req.valid    = 1'b1;
            data_mem_req.addr     = ex_mem_alu_result;
            data_mem_req.do_write = 4'b1111; // Write a full 32-bit word
            data_mem_req.data     = ex_mem_reg_data2;
        end
    end

    // MEM/WB Pipeline Registers: Pass memory read data or ALU result
    // New pipeline registers for load processing
    logic [2:0]  mem_wb_funct3;
    logic [31:0] mem_wb_effective_addr;
    logic [31:0] mem_wb_data, mem_wb_imm;
    logic [6:0]  mem_wb_opcode;
    always_ff @(posedge clk) begin
        if (reset || branch_taken_reg) begin
            mem_wb_data      <= 32'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_rd        <= 5'b0;
            mem_wb_imm <= 32'b0;  // Add this line


        end else begin
            // When reading from memory, use the data_mem_rsp;
            // otherwise, pass the ALU result.
            if (ex_mem_mem_read)
                mem_wb_data <= data_mem_rsp.data;
            else
                mem_wb_data <= ex_mem_alu_result;
    
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_rd        <= ex_mem_rd;
            mem_wb_opcode <= ex_mem_opcode;
            mem_wb_imm <= ex_mem_imm;
            mem_wb_funct3 <= ex_mem_funct3;
            mem_wb_effective_addr <= ex_mem_alu_result;
        end
    end

    //--------------------------------------------------------------------------
    // WB Stage: Write Back Results to the Register File
    //--------------------------------------------------------------------------
    // Load data processing logic
    logic [31:0] load_adjusted;
    always_comb begin
        case(mem_wb_funct3)
            3'b000: begin // LB (byte load)
                case(mem_wb_effective_addr[1:0])
                    2'b00: load_adjusted = {{24{mem_wb_data[7]}},  mem_wb_data[7:0]};
                    2'b01: load_adjusted = {{24{mem_wb_data[15]}}, mem_wb_data[15:8]};
                    2'b10: load_adjusted = {{24{mem_wb_data[23]}}, mem_wb_data[23:16]};
                    2'b11: load_adjusted = {{24{mem_wb_data[31]}}, mem_wb_data[31:24]};
                endcase
            end
            3'b001: begin // LH (halfword)
                load_adjusted = mem_wb_effective_addr[1] ? 
                            {{16{mem_wb_data[31]}}, mem_wb_data[31:16]} : 
                            {{16{mem_wb_data[15]}}, mem_wb_data[15:0]};
            end
            3'b010: load_adjusted = mem_wb_data; // LW
            3'b100: begin // LBU
                case(mem_wb_effective_addr[1:0])
                    2'b00: load_adjusted = {24'b0, mem_wb_data[7:0]};
                    2'b01: load_adjusted = {24'b0, mem_wb_data[15:8]};
                    2'b10: load_adjusted = {24'b0, mem_wb_data[23:16]};
                    2'b11: load_adjusted = {24'b0, mem_wb_data[31:24]};
                endcase
            end
            3'b101: begin // LHU
                load_adjusted = mem_wb_effective_addr[1] ? 
                            {16'b0, mem_wb_data[31:16]} : 
                            {16'b0, mem_wb_data[15:0]};
            end
            default: load_adjusted = mem_wb_data;
        endcase
    end
    
    // The register file is written using signals from the MEM/WB stage.
    assign wb_reg_write  = mem_wb_reg_write;
    assign wb_rd         = mem_wb_rd;
    // Final writeback selection
    assign wb_write_data = (mem_wb_opcode == 7'b0110111) ? mem_wb_imm :  // LUI
                        (mem_wb_opcode == 7'b0000011) ? load_adjusted : // Loads
                        mem_wb_data;  
                                                        // Default
    always_ff @(posedge clk) begin
        $display("Written back data: %d\n", wb_write_data);
        $display("Reg Write? %d\n", wb_reg_write);
        $display("Register: %d\n", wb_rd);
        //$display("Counter: %d\n", ctr);
        if (ctr >= 1000) begin
            $finish;
        end else begin
            ctr <= ctr + 1;
        end
        
    end

endmodule

`endif

typedef logic [4:0] regname_t;    // For rs1, rs2, rd
typedef logic [6:0] funct7_t;    // For funct7
typedef logic [2:0] funct3_t;    // For funct3
typedef logic [6:0] opcode_t;    // For opcode
typedef logic [11:0] imm12_t;    // For imm_i and imm_s
typedef logic [12:0] imm13_t;    // For imm_b
typedef logic [19:0] imm20_t;    // For imm_u and imm_j
typedef logic [20:0] imm21_t;    // For imm_u and imm_j

function void print_instruction(logic [31:0] pc, logic [31:0] instruction);
    // Declare variables to hold decoded instruction fields
    regname_t rs1, rs2, rd;
    funct7_t funct7;
    funct3_t funct3;
    opcode_t opcode;
    imm12_t imm_i, imm_s;
    imm20_t imm_u;
    imm21_t imm_j;
    imm13_t imm_b;

    // Parse individual fields
    opcode = instruction[6:0];
    rd = instruction[11:7];
    funct3 = instruction[14:12];;
    rs1 = instruction[19:15];
    rs2 = instruction[24:20];
    funct7 = instruction[31:25];
    
    // Parse immediates with proper sign extension and concatenation
    imm_i = $signed(instruction[31:20]);                      // Immediate for I-type
    imm_s = $signed({instruction[31:25], instruction[11:7]}); // Immediate for S-type
    imm_b = $signed({instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0}); // Immediate for B-type
    imm_u = instruction[31:12];                      // Immediate for U-type (upper 20 bits shifted left)
    imm_j = $signed({instruction[31], instruction[30:21], instruction[20], instruction[19:12], 1'b0}); // Immediate for J-type

    // Print PC and instruction bytes
    $write("%8h: %8h   ", pc, instruction);

    // Use the decoded fields to format the instruction
    case (opcode)
        7'b0110111: begin
            $write("lui     %s,0x%h", reg_name(rd), imm_u);
            //$write("   // Load Upper Immediate: Set %s to upper 20 bits of 0x%h", reg_name(rd), imm_u);
        end
        7'b0010111: begin
            $write("auipc   %s,0x%h", reg_name(rd), imm_u);
            //$write("   // Add Upper Immediate to PC: %s = pc + (0x%h << 12)", reg_name(rd), imm_u);
        end
        7'b1101111: begin
            $write("jal     %s,0x%h", reg_name(rd), $signed(imm_j));
            //$write("   // Jump and Link: %s = pc + 4; pc += %0d", reg_name(rd), $signed(imm_j));
        end
        7'b1100111: begin
            $write("jalr    %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
            //$write("   // Jump and Link Register: %s = pc + 4; pc = %s + %0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
        end
        7'b1100011: begin
            case (funct3)
                3'b000: begin
                    $write("beq     %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                    //$write("   // Branch if Equal: if (%s == %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                3'b001: begin
                    $write("bne     %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                    //$write("   // Branch if Not Equal: if (%s != %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                3'b100: begin
                    $write("blt     %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                    //$write("   // Branch if Less Than: if (%s < %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                3'b101: begin
                    $write("bge     %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                   //$write("   // Branch if Greater or Equal: if (%s >= %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                3'b110: begin
                    $write("bltu    %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                    //$write("   // Branch if Less Than Unsigned: if (%s < %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                3'b111: begin
                    $write("bgeu    %s,%s,0x%h", reg_name(rs1), reg_name(rs2), pc + {19'b0, $signed(imm_b)});
                    //$write("   // Branch if Greater or Equal Unsigned: if (%s >= %s) pc += %0d", reg_name(rs1), reg_name(rs2), $signed(imm_b));
                end
                default: $write("UNKNOWN");
            endcase
        end
        7'b0000011: begin
            case (funct3)
                3'b000: begin
                    $write("lb      %s,%0d(%s)", reg_name(rd), $signed(imm_i), reg_name(rs1));
                    //$write("   // Load Byte: %s = sign_extend(mem[%s + %0d][7:0])", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b001: begin
                    $write("lh      %s,%0d(%s)", reg_name(rd), $signed(imm_i), reg_name(rs1));
                    //$write("   // Load Halfword: %s = sign_extend(mem[%s + %0d][15:0])", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b010: begin
                    $write("lw      %s,%0d(%s)", reg_name(rd), $signed(imm_i), reg_name(rs1));
                    //$write("   // Load Word: %s = mem[%s + %0d][31:0]", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b100: begin
                    $write("lbu     %s,%0d(%s)", reg_name(rd), $signed(imm_i), reg_name(rs1));
                    //$write("   // Load Byte Unsigned: %s = zero_extend(mem[%s + %0d][7:0])", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b101: begin
                    $write("lhu     %s,%0d(%s)", reg_name(rd), $signed(imm_i), reg_name(rs1));
                    //$write("   // Load Halfword Unsigned: %s = zero_extend(mem[%s + %0d][15:0])", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                default: $write("UNKNOWN");
            endcase
        end
        7'b0100011: begin
            case (funct3)
                3'b000: begin
                    $write("sb      %s,%0d(%s)", reg_name(rs2), $signed(imm_s), reg_name(rs1));
                    //$write("   // Store Byte: mem[%s + %0d][7:0] = %s[7:0]", reg_name(rs1), $signed(imm_s), reg_name(rs2));
                end
                3'b001: begin
                    $write("sh      %s,%0d(%s)", reg_name(rs2), $signed(imm_s), reg_name(rs1));
                    //$write("   // Store Halfword: mem[%s + %0d][15:0] = %s[15:0]", reg_name(rs1), $signed(imm_s), reg_name(rs2));
                end
                3'b010: begin
                    $write("sw      %s,%0d(%s)", reg_name(rs2), $signed(imm_s), reg_name(rs1));
                    //$write("   // Store Word: mem[%s + %0d][31:0] = %s", reg_name(rs1), $signed(imm_s), reg_name(rs2));
                end
                default: $write("UNKNOWN");
            endcase
        end
        7'b0010011: begin
            case (funct3)
                3'b000: begin
                    $write("addi    %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // Add Immediate: %s = %s + %0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b010: begin
                    $write("slti    %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // Set Less Than Immediate: %s = (%s < %0d) ? 1 : 0", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b011: begin
                    $write("sltiu   %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // Set Less Than Immediate Unsigned: %s = (%s < %0d) ? 1 : 0", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b100: begin
                    $write("xori    %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // XOR Immediate: %s = %s ^ %0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b110: begin
                    $write("ori     %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // OR Immediate: %s = %s | %0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b111: begin
                    $write("andi    %s,%s,%0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                    //$write("   // AND Immediate: %s = %s & %0d", reg_name(rd), reg_name(rs1), $signed(imm_i));
                end
                3'b001: begin
                    $write("slli    %s,%s,%0d", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                    //$write("   // Shift Left Logical Immediate: %s = %s << %0d", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                end
                3'b101: begin
                    if (funct7[5]) begin
                        $write("srai    %s,%s,%0d", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                        //$write("   // Shift Right Arithmetic Immediate: %s = %s >> %0d (arithmetic)", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                    end else begin
                        $write("srli    %s,%s,%0d", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                        //$write("   // Shift Right Logical Immediate: %s = %s >> %0d (logical)", reg_name(rd), reg_name(rs1), imm_i[4:0]);
                    end
                end
                default: $write("UNKNOWN");
            endcase
        end
        7'b0110011: begin
            case (funct3)
                3'b000: begin
                    if (funct7[5]) begin
                        $write("sub     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        //$write("   // Subtract: %s = %s - %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    end else begin
                        $write("add     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        //$write("   // Add: %s = %s + %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    end
                end
                3'b001: begin
                    $write("sll     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    //$write("   // Shift Left Logical: %s = %s << %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                3'b010: begin
                    $write("slt     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    //$write("   // Set Less Than: %s = (%s < %s) ? 1 : 0", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                3'b011: begin
                    $write("sltu    %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    //$write("   // Set Less Than Unsigned: %s = (%s < %s) ? 1 : 0", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                3'b100: begin
                    $write("xor     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    //$write("   // XOR: %s = %s ^ %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                3'b101: begin
                    if (funct7[5]) begin
                        $write("sra     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        //$write("   // Shift Right Arithmetic: %s = %s >> %s (arithmetic)", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    end else begin
                        $write("srl     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                        //$write("   // Shift Right Logical: %s = %s >> %s (logical)", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    end
                end
                3'b110: begin
                    $write("or      %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                    //$write("   // OR: %s = %s | %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                3'b111: begin
                    $write("and     %s,%s,%s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                   //$write("   // AND: %s = %s & %s", reg_name(rd), reg_name(rs1), reg_name(rs2));
                end
                default: $write("UNKNOWN");
            endcase
        end
        7'b1110011: begin
            if (instruction == 32'h00000073) begin
                $write("ecall");
                //$write("   // Environment Call");
            end else if (instruction == 32'h00100073) begin
                $write("ebreak");
                //$write("   // Environment Break");
            end else begin
                $write("UNKNOWN");
            end
        end
        default: $write("UNKNOWN");
    endcase

    $write("\n");
endfunction

// Helper function to convert register numbers to names
function string reg_name(regname_t reg_num);
    case (reg_num)
        5'd0: return "zero";
        5'd1: return "ra";
        5'd2: return "sp";
        5'd3: return "gp";
        5'd4: return "tp";
        5'd5: return "t0";
        5'd6: return "t1";
        5'd7: return "t2";
        5'd8: return "s0";
        5'd9: return "s1";
        5'd10: return "a0";
        5'd11: return "a1";
        5'd12: return "a2";
        5'd13: return "a3";
        5'd14: return "a4";
        5'd15: return "a5";
        5'd16: return "a6";
        5'd17: return "a7";
        5'd18: return "s2";
        5'd19: return "s3";
        5'd20: return "s4";
        5'd21: return "s5";
        5'd22: return "s6";
        5'd23: return "s7";
        5'd24: return "s8";
        5'd25: return "s9";
        5'd26: return "s10";
        5'd27: return "s11";
        5'd28: return "t3";
        5'd29: return "t4";
        5'd30: return "t5";
        5'd31: return "t6";
        default: return $sformatf("x%0d", reg_num);
    endcase
endfunction


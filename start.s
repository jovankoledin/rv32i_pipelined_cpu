.extern halt
.globl _start

.text
_start:
    # Set up the stack pointer.
    li      sp, 0x00030000 - 16        # Initialize stack pointer
    ###########################################################################
    # Test 1: R-type Arithmetic Instructions (ADD, SUB, AND, SLL)
    ###########################################################################
    li      t0, 10                     # t0 = 10
    li      t1, 5                      # t1 = 5
                                  # Delay to avoid hazards
    add     t2, t0, t1                 # t2 = 10 + 5 = 15 (R-type ADD)
                                  # Delay so t2 is written back
    li      t3, 15
                                  # Delay to ensure li completes
    beq     t2, t3, r_sub_test          # Check ADD result
    j       error


r_sub_test:
                                  # Delay for hazard avoidance
    sub     t4, t0, t1                 # t4 = 10 - 5 = 5 (R-type SUB)
                                  # Delay so t4 is safely available
    li      t5, 5
                                  # Delay after li
    beq     t4, t5, r_logic_test       # Check SUB result
    j       error

r_logic_test:
                                  # Delay before using new result
    and     t6, t0, t1                 # t6 = 10 & 5 (R-type AND)
                                  # Delay for safe writeback
    li      t5, 0                    # Expected result: 0
                                  # Delay before branch
    beq     t6, t5, r_shift_test
    j       error

r_shift_test:
                                  # Insert delay for hazard safety
    sll     t3, t0, t1                 # t8 = 10 << 5 = 320 (R-type SLL)
                                  # Delay so t8 is updated
    li      t4, 320
                                  # Extra delay before branch
    beq     t3, t4, itype_test
    j       error

    ###########################################################################
    # Test 2: I-type Instructions: ADDI and Loads (LW, LB, LHU)
    ###########################################################################
itype_test:
                                  # Delay before ADDI
    addi    t0, t0, 5                  # t0 = previous t0 + 5
                                  # Delay for safe register update
    li      t1, 15
                                  # Delay after li
    beq     t0, t1, load_store_test
    j       error

    ###########################################################################
    # Test 3: Load/Store Word (S-type LW/SW)
    ###########################################################################
load_store_test:
                                  # Delay to separate test phases
    li      t2, 0xAABBCCDD            # Test word value
                                  # Delay after li
    sw      t2, 0(sp)                 # Store word at address sp
                                  # Delay between store and load
    lw      t3, 0(sp)                 # Load word from sp into t3
                                  # Delay for load data to be written back
    beq     t2, t3, byte_test
    j       error

    ###########################################################################
    # Test 4: Load/Store Byte (SB, LB)
    ###########################################################################
byte_test:
                                  # Delay for hazard safety
    li      t4, 0x7F                 # Test byte value
                                  # Delay after li
    sb      t4, 4(sp)                # Store byte at sp+4
                                  # Delay between store and load
    lb      t5, 4(sp)                # Load byte (signed) from sp+4
                                  # Delay to ensure value update
    beq     t4, t5, halfword_test
    j       error

    ###########################################################################
    # Test 5: Load/Store Halfword (SH, LHU)
    ###########################################################################
halfword_test:
                                  # Insert delay for hazard safety
    li      t6, 0x1234              # Test halfword value
                                  # Delay
    sh      t6, 8(sp)               # Store halfword at sp+8
                                  # Delay between store and load
    lhu     t5, 8(sp)               # Load halfword unsigned from sp+8
                                  # Delay for correct data update
    beq     t6, t5, branch_test
    j       error

    ###########################################################################
    # Test 6: Branch Instructions (B-type: BEQ, BNE, BLT, BGE)
    ###########################################################################
branch_test:
                                  # Delay for branch hazard safety
    li      t0, 100
                                  # Delay
    li      t1, 100
                                  # Delay before branch evaluation
    beq     t0, t1, bne_test          # Branch since 100 == 100
    j       error

bne_test:
                                  # Delay for hazard safety
    li      t2, 200
                                  # Delay after li
    li      t3, 300
                                  # Delay before branch check
    bne     t2, t3, blt_test          # Branch since 200 != 300
    j       error

blt_test:
                                  # Insert delay
    li      s0, -5
                                  # Delay after li
    li      s1, 10
                                  # Delay for data update
    blt     s0, s1, bge_test          # Branch taken (-5 < 10)
    j       error

bge_test:
                                  # Delay for hazard safety
    li      s2, 50
                                  # Delay after li
    li      s3, 50
                                  # Delay before branch evaluation
    bge     s2, s3, lui_test          # Branch taken (50 >= 50)
    j       error

    ###########################################################################
    # Test 7: U-type Instructions (LUI and AUIPC)
    ###########################################################################
lui_test:
                                  # Delay for hazard avoidance
    lui     t0, 0x12345             # t0 = 0x12345000 (U-type LUI)
                                  # Delay after LUI
    li      t1, 0x12345000
                                  # Delay for li update
    beq     t0, t1, auipc_test
    j       error

auipc_test:
                                  # Delay before AUIPC
    auipc   t2, 0x1                 # t2 = PC + 0x1000 (U-type AUIPC)
                                  # Delay for safe update
    j       jal_test

    ###########################################################################
    # Test 8: J-type Instructions (JAL and JALR)
    ###########################################################################
jal_test:
                                  # Delay before jump instruction
    jal     ra, jal_target          # JAL: Jump to jal_target, saving return address in ra
                                  # Delay after JAL (should not be reached)
    j       error

jal_target:
                                  # Delay for hazard safety in return
    jalr    zero, ra, 0             # JALR: Jump back to instruction after jal_test
                                  # Delay before proceeding
    j       success

success:
    addi    t1, t1, 96            # Delay in success path
    call    halt                  # Halt execution (test passed)
                                  # Delay after call
    j       success

error:
                                  # Delay in error path
    addi    t1, t1, 69 
    call    halt                    # Halt execution to signal error
    j       error                    # Run forever 

#.extern main
.globl _start

.text

_start:
#
# Uncomment / add to / etc to test lab 2


#                        auipc   a4,0x1000
#                        addi    a4,a4,-436
#                        add a5,a5,a4
#                        add a5,a5,a4
#
# place additional test instructions here
#
#
#






### Everything below here is not required for lab2.
######
#
#  halt
#        li a0, 0x0002FFFC
#        sw zero, 0(a0)
        
# Eventually this is is the start of your code for future labs (by lab 4 this will be needed)
    li      sp, (0x00030000 - 16)
    call    main
    call    halt
    j       _start


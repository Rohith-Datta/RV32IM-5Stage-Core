.global _start
_start:
 li x1,10
 li x2,20
 add x3,x1,x2
 mul x4,x1,x2
 div x5,x4,x1
 div x6,x1,x0
 clz x7,x1
 cpop x8,x1
 max x9,x1,x2
 min x10,x1,x2
 andn x11,x1,x2
 li x12,0x3fc00000
 fmv.w.x f12,x12
 li x15,0x40200000
 fmv.w.x f15,x15
 fadd.s f13,f12,f15,rne
 li x16,0x40000000
 fmv.w.x f16,x16
 fmul.s f14,f13,f16,rne
 li x17,0x1000
 sw x4,0(x17)
 lw x18,0(x17)
 csrr x19,cycle
 csrr x20,instret
 csrr x21,0xc05
 beq x1,x1,1f
 li x26,99
1: li x26,1
 csrr x22,0xc07
2: j 2b

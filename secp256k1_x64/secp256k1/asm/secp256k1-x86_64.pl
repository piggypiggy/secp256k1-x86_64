#! /usr/bin/env perl
# Copyright 2018 The GmSSL Project. All Rights Reserved.
#
# This work is supported by the National Key Research and Development Program
# of China NO.2018YFB0803601 and Intel.
#
# Copyright 2014-2016 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html


##############################################################################
#                                                                            #
# Copyright 2014 Intel Corporation                                           #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License");            #
# you may not use this file except in compliance with the License.           #
# You may obtain a copy of the License at                                    #
#                                                                            #
#    http://www.apache.org/licenses/LICENSE-2.0                              #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#                                                                            #
##############################################################################
#                                                                            #
#  Developers and authors:                                                   #
#  Shay Gueron (1, 2), and Vlad Krasnov (1)                                  #
#  (1) Intel Corporation, Israel Development Center                          #
#  (2) University of Haifa                                                   #
#  Reference:                                                                #
#  S.Gueron and V.Krasnov, "Fast Prime Field Elliptic Curve Cryptography with#
#                           256 Bit Primes"                                  #
#                                                                            #
##############################################################################


##############################################################################
#                                                                            #
# Copyright 2020 Meng-Shan Jiang                                             #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License");            #
# you may not use this file except in compliance with the License.           #
# You may obtain a copy of the License at                                    #
#                                                                            #
#    http://www.apache.org/licenses/LICENSE-2.0                              #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#                                                                            #
##############################################################################
#                                                                            #
# The original work is to implement sm2 point arithmetic, I modified         #
# it to work on secp256k1 :).                                                #
#                                                                            #
##############################################################################

$flavour = shift;
$output  = shift;

if ($flavour =~ /\./) { $output = $flavour; undef $flavour; }

$win64=0; $win64=1 if ($flavour =~ /[nm]asm|mingw64/ || $output =~ /\.asm$/);

$0 =~ m/(.*[\/\\])[^\/\\]+$/; $dir=$1;
( $xlate="${dir}x86_64-xlate.pl" and -f $xlate ) or
( $xlate="${dir}../../perlasm/x86_64-xlate.pl" and -f $xlate) or
die "can't locate x86_64-xlate.pl";

open OUT,"| \"$^X\" \"$xlate\" $flavour \"$output\"";
*STDOUT=*OUT;

$avx = 2;
$addx = 1;

$code.=<<___;
.text
.hidden	cpu_info

.extern	cpu_info

# The polynomial
.align 64
.Lpoly:
.quad 0xfffffffefffffc2f, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff

# 2^512 mod P
.LRR:
.quad 0x000007a2000e90a1, 0x0000000000000001, 0x0000000000000000, 0x0000000000000000

.LOne:
.long 1,1,1,1,1,1,1,1
.LTwo:
.long 2,2,2,2,2,2,2,2
.LThree:
.long 3,3,3,3,3,3,3,3
.LONE_mont:
.quad 0x00000001000003d1, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000
.LK:
.quad 0xd838091dd2253531
___

{
################################################################################
# void secp256k1_mul_by_2(uint64_t res[4], uint64_t a[4]);

my ($a0,$a1,$a2,$a3)=map("%r$_",(8..11));
my ($t0,$t1,$t2,$t3,$t4)=("%rax","%rdx","%rcx","%r12","%r13");
my ($r_ptr,$a_ptr,$b_ptr)=("%rdi","%rsi","%rdx");

$code.=<<___;

.globl	secp256k1_mul_by_2
.type	secp256k1_mul_by_2,\@function,2
.align	64
secp256k1_mul_by_2:
    push	%r12
    push	%r13

    mov	8*0($a_ptr), $a0
    xor	$t4,$t4
    mov	8*1($a_ptr), $a1
    add	$a0, $a0		# a0:a3+a0:a3
    mov	8*2($a_ptr), $a2
    adc	$a1, $a1
    mov	8*3($a_ptr), $a3
    lea	.Lpoly(%rip), $a_ptr
     mov	$a0, $t0
    adc	$a2, $a2
    adc	$a3, $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	8*0($a_ptr), $a0
     mov	$a2, $t2
    sbb	8*1($a_ptr), $a1
    sbb	8*2($a_ptr), $a2
     mov	$a3, $t3
    sbb	8*3($a_ptr), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop	%r13
    pop	%r12
    ret
.size	secp256k1_mul_by_2,.-secp256k1_mul_by_2

################################################################################
# void secp256k1_div_by_2(uint64_t res[4], uint64_t a[4]);
.globl	secp256k1_div_by_2
.type	secp256k1_div_by_2,\@function,2
.align	32
secp256k1_div_by_2:
    push	%r12
    push	%r13

    mov	8*0($a_ptr), $a0
    mov	8*1($a_ptr), $a1
    mov	8*2($a_ptr), $a2
     mov	$a0, $t0
    mov	8*3($a_ptr), $a3
    lea	.Lpoly(%rip), $a_ptr

     mov	$a1, $t1
    xor	$t4, $t4
    add	8*0($a_ptr), $a0
     mov	$a2, $t2
    adc	8*1($a_ptr), $a1
    adc	8*2($a_ptr), $a2
     mov	$a3, $t3
    adc	8*3($a_ptr), $a3
    adc	\$0, $t4
    xor	$a_ptr, $a_ptr		# borrow $a_ptr
    test	\$1, $t0

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    cmovz	$t2, $a2
    cmovz	$t3, $a3
    cmovz	$a_ptr, $t4

    mov	$a1, $t0		# a0:a3>>1
    shr	\$1, $a0
    shl	\$63, $t0
    mov	$a2, $t1
    shr	\$1, $a1
    or	$t0, $a0
    shl	\$63, $t1
    mov	$a3, $t2
    shr	\$1, $a2
    or	$t1, $a1
    shl	\$63, $t2
    shr	\$1, $a3
    shl	\$63, $t4
    or	$t2, $a2
    or	$t4, $a3

    mov	$a0, 8*0($r_ptr)
    mov	$a1, 8*1($r_ptr)
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop	%r13
    pop	%r12
    ret
.size	secp256k1_div_by_2,.-secp256k1_div_by_2

################################################################################
# void secp256k1_mul_by_3(uint64_t res[4], uint64_t a[4]);
.globl	secp256k1_mul_by_3
.type	secp256k1_mul_by_3,\@function,2
.align	32
secp256k1_mul_by_3:
    push	%r12
    push	%r13

    mov	8*0($a_ptr), $a0
    xor	$t4, $t4
    mov	8*1($a_ptr), $a1
    add	$a0, $a0		# a0:a3+a0:a3
    mov	8*2($a_ptr), $a2
    adc	$a1, $a1
    mov	8*3($a_ptr), $a3
     mov	$a0, $t0
    adc	$a2, $a2
    adc	$a3, $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    cmovc	$t2, $a2
    cmovc	$t3, $a3

    xor	$t4, $t4
    add	8*0($a_ptr), $a0	# a0:a3+=a_ptr[0:3]
    adc	8*1($a_ptr), $a1
     mov	$a0, $t0
    adc	8*2($a_ptr), $a2
    adc	8*3($a_ptr), $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop %r13
    pop %r12
    ret
.size	secp256k1_mul_by_3,.-secp256k1_mul_by_3

################################################################################
# void secp256k1_add(uint64_t res[4], uint64_t a[4], uint64_t b[4]);
.globl	secp256k1_add
.type	secp256k1_add,\@function,3
.align	32
secp256k1_add:
    push	%r12
    push	%r13

    mov	8*0($a_ptr), $a0
    xor	$t4, $t4
    mov	8*1($a_ptr), $a1
    mov	8*2($a_ptr), $a2
    mov	8*3($a_ptr), $a3
    lea	.Lpoly(%rip), $a_ptr

    add	8*0($b_ptr), $a0
    adc	8*1($b_ptr), $a1
     mov	$a0, $t0
    adc	8*2($b_ptr), $a2
    adc	8*3($b_ptr), $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	8*0($a_ptr), $a0
     mov	$a2, $t2
    sbb	8*1($a_ptr), $a1
    sbb	8*2($a_ptr), $a2
     mov	$a3, $t3
    sbb	8*3($a_ptr), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop %r13
    pop %r12
    ret
.size	secp256k1_add,.-secp256k1_add

################################################################################
# void secp256k1_sub(uint64_t res[4], uint64_t a[4], uint64_t b[4]);
.globl	secp256k1_sub
.type	secp256k1_sub,\@function,3
.align	32
secp256k1_sub:
    push	%r12
    push	%r13

    mov	8*0($a_ptr), $a0
    xor	$t4, $t4
    mov	8*1($a_ptr), $a1
    mov	8*2($a_ptr), $a2
    mov	8*3($a_ptr), $a3
    lea	.Lpoly(%rip), $a_ptr

    sub	8*0($b_ptr), $a0
    sbb	8*1($b_ptr), $a1
     mov	$a0, $t0
    sbb	8*2($b_ptr), $a2
    sbb	8*3($b_ptr), $a3
     mov	$a1, $t1
    sbb	\$0, $t4

    add	8*0($a_ptr), $a0
     mov	$a2, $t2
    adc	8*1($a_ptr), $a1
    adc	8*2($a_ptr), $a2
     mov	$a3, $t3
    adc	8*3($a_ptr), $a3
    test	$t4, $t4

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovz	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovz	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop %r13
    pop %r12
    ret
.size	secp256k1_sub,.-secp256k1_sub

################################################################################
# void secp256k1_neg(uint64_t res[4], uint64_t a[4]);
.globl	secp256k1_neg
.type	secp256k1_neg,\@function,2
.align	32
secp256k1_neg:
    push	%r12
    push	%r13

    xor	$a0, $a0
    xor	$a1, $a1
    xor	$a2, $a2
    xor	$a3, $a3
    xor	$t4, $t4

    sub	8*0($a_ptr), $a0
    sbb	8*1($a_ptr), $a1
    sbb	8*2($a_ptr), $a2
     mov	$a0, $t0
    sbb	8*3($a_ptr), $a3
    lea	.Lpoly(%rip), $a_ptr
     mov	$a1, $t1
    sbb	\$0, $t4

    add	8*0($a_ptr), $a0
     mov	$a2, $t2
    adc	8*1($a_ptr), $a1
    adc	8*2($a_ptr), $a2
     mov	$a3, $t3
    adc	8*3($a_ptr), $a3
    test	$t4, $t4

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovz	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovz	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop %r13
    pop %r12
    ret
.size	secp256k1_neg,.-secp256k1_neg

################################################################################
# void secp256k1_reduce(uint64_t res[4], uint64_t a[4]);
.globl	secp256k1_reduce
.type	secp256k1_reduce,\@function,2
.align	32
secp256k1_reduce:
    push	%r12
    push	%r13

    mov 8*0($a_ptr), $a0
    mov 8*1($a_ptr), $a1
    mov 8*2($a_ptr), $a2
    mov $a0, $t0
    mov 8*3($a_ptr), $a3
    mov	.LONE_mont+8*0(%rip), $t3
    mov $a1, $t1
    xor	$t4, $t4

    add     $t3, $a0
    mov $a2, $t2
    adc     \$0, $a1
    adc     \$0, $a2
    mov $a3, $t3
    adc     \$0, $a3
    test	$t4, $t4

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovz	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovz	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    pop %r13
    pop %r12
    ret
.size	secp256k1_reduce,.-secp256k1_reduce
___
}
{
my ($r_ptr,$a_ptr,$b_org,$b_ptr)=("%rdi","%rsi","%rdx","%rbx");
my ($acc0,$acc1,$acc2,$acc3,$acc4,$acc5,$acc6,$acc7)=map("%r$_",(8..15));
my ($t0,$t1,$t2,$t3,$t4)=("%rcx","%rbp","%rbx","%rdx","%rax");
my ($poly1,$poly3)=($acc6,$acc7);

$code.=<<___;

################################################################################
# void secp256k1_mul_word(
#   uint64_t res[4],
#   uint64_t in[4],
#   uint64_t w);
.globl	secp256k1_mul_word
.type	secp256k1_mul_word,\@function,3
.align	32
secp256k1_mul_word:
    push    %rbp
    push    %rbx
    push	%r12
    push	%r13

    mov	$b_org, %rax
    mov	8*0($a_ptr), $acc1
    mov	8*1($a_ptr), $acc2
    mov	8*2($a_ptr), $acc3
    mov	8*3($a_ptr), $acc4

    mov	%rax, $t1
    mulq	$acc1
    mov	%rax, $acc0
    mov	$t1, %rax
    mov	%rdx, $acc1

    mulq	$acc2
    add	%rax, $acc1
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc2

    mulq	$acc3
    add	%rax, $acc2
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc3

    mulq	$acc4
    add	%rax, $acc3
    adc	\$0, %rdx
     mov	.LONE_mont+8*0(%rip), %rax 
    xor	$acc5, $acc5
    mov	%rdx, $acc4

    ########################################################################
    # reduction
.reduce:

    mulq    $acc4
    add %rax, $acc0
    mov \$0, $acc4
    adc %rdx, $acc1
    adc \$0, $acc2
    adc \$0, $acc3
    adc \$0, $acc4
     mov $acc0, $t0
     mov $acc1, $t1
    cmp \$0, $acc4
    jl    .reduce

    ########################################################################
    # Branch-less conditional subtraction of P

    sub	.Lpoly+8*0(%rip), $acc0
     mov	$acc2, $t2
    sbb	.Lpoly+8*1(%rip), $acc1
    sbb	.Lpoly+8*2(%rip), $acc2
     mov	$acc3, $t3
    sbb	.Lpoly+8*3(%rip), $acc3
    sbb	\$0, $acc4

    cmovc	$t0, $acc0
    cmovc	$t1, $acc1
    mov	$acc0, 8*0($r_ptr)
    cmovc	$t2, $acc2
    mov	$acc1, 8*1($r_ptr)
    cmovc	$t3, $acc3
    mov	$acc2, 8*2($r_ptr)
    mov	$acc3, 8*3($r_ptr)

    pop 	%r13
    pop 	%r12
    pop     %rbx
    pop     %rbp

    ret
.size	secp256k1_mul_word,.-secp256k1_mul_word
___

$code.=<<___;
################################################################################
# void secp256k1_to_mont(
#   uint64_t res[4],
#   uint64_t in[4]);
.globl	secp256k1_to_mont
.type	secp256k1_to_mont,\@function,2
.align	32
secp256k1_to_mont:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx  # 0x80000 : BMI2 SUPPORT, 0x100 : ADX SUPPORT
    and	cpu_info+8(%rip), %ecx
___
$code.=<<___;
    lea	.LRR(%rip), $b_org
    jmp	.Lmul_mont
.size	secp256k1_to_mont,.-secp256k1_to_mont

################################################################################
# void secp256k1_mul_mont(
#   uint64_t res[4],
#   uint64_t a[4],
#   uint64_t b[4]);

.globl	secp256k1_mul_mont
.type	secp256k1_mul_mont,\@function,3
.align	32
secp256k1_mul_mont:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx
    and	cpu_info+8(%rip), %ecx
___
$code.=<<___;
.Lmul_mont:
    push	%rbp
    push	%rbx
    push	%r12
    push	%r13
    push	%r14
    push	%r15
___
$code.=<<___	if ($addx);
    cmp	\$0x80100, %ecx
    je	.Lmul_montx
___
$code.=<<___;
    mov	$b_org, $b_ptr
    mov	8*0($b_org), %rax
    mov	8*0($a_ptr), $acc1
    mov	8*1($a_ptr), $acc2
    mov	8*2($a_ptr), $acc3
    mov	8*3($a_ptr), $acc4

    call	__secp256k1_mul_montq
___
$code.=<<___	if ($addx);
    jmp	.Lmul_mont_done

.align	32
.Lmul_montx:
    mov	$b_org, $b_ptr
    mov	8*0($b_org), %rdx
    mov	8*0($a_ptr), $acc1
    mov	8*1($a_ptr), $acc2
    mov	8*2($a_ptr), $acc3
    mov	8*3($a_ptr), $acc4
    lea	-128($a_ptr), $a_ptr	# control u-op density

    call	__secp256k1_mul_montx
___
$code.=<<___;
.Lmul_mont_done:
    pop	%r15
    pop	%r14
    pop	%r13
    pop	%r12
    pop	%rbx
    pop	%rbp
    ret
.size	secp256k1_mul_mont,.-secp256k1_mul_mont

.type	__secp256k1_mul_montq,\@abi-omnipotent
.align	32
__secp256k1_mul_montq:
    ########################################################################
    # Multiply a by b[0]

    mov	%rax, $t1
    mulq	$acc1
    mov	.Lpoly+8*1(%rip),$poly1
    mov	%rax, $acc0
    mov	$t1, %rax
    mov	%rdx, $acc1

    mulq	$acc2
    mov	.Lpoly+8*3(%rip),$poly3
    add	%rax, $acc1
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc2

    mulq	$acc3
    add	%rax, $acc2
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc3

    mulq	$acc4
    add	%rax, $acc3
     mov	$acc0, %rax
    adc	\$0, %rdx
    xor	$acc5, $acc5
    mov	%rdx, $acc4
     mov .LK+8*0(%rip), $poly3

    ########################################################################
    # First reduction step

    mov $acc0, $t1
    mulq $poly3       # rax = poly3 * rax mod 2^64
    add %rax, $acc4
    mov	.LONE_mont+8*0(%rip),$poly1
    adc \$0, $acc5
    mulq $poly1
    sub	%rax, $acc0
    sbb	%rdx, $acc1
    sbb	\$0, $acc2
    mov	8*1($b_ptr), %rax
    sbb	\$0, $acc3
    sbb	\$0, $acc4
    sbb \$0, $acc5
    xor $acc0, $acc0

    ########################################################################
    # Multiply by b[1], C = acc4,3,2,1

    mov	%rax, $t1
    mulq	8*0($a_ptr)
    add	%rax, $acc1
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*1($a_ptr)
    add	$t0, $acc2
    adc	\$0, %rdx
    add	%rax, $acc2
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*2($a_ptr)
    add	$t0, $acc3
    adc	\$0, %rdx
    add	%rax, $acc3
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*3($a_ptr)
    add	$t0, $acc4
    adc	\$0, %rdx
    add	%rax, $acc4
     mov	$acc1, %rax
    adc	%rdx, $acc5
    adc	\$0, $acc0

    ########################################################################
    # Second reduction step

    mov $acc1, $t1
    mulq $poly3       # rax = poly3 * rax mod 2^64
    add %rax, $acc5
    # mov	.LONE_mont+8*0(%rip),$poly1
    adc \$0, $acc0
    mulq $poly1
    sub	%rax, $acc1
    sbb	%rdx, $acc2
    sbb	\$0, $acc3
    mov	8*2($b_ptr), %rax
    sbb	\$0, $acc4
    sbb	\$0, $acc5
    sbb \$0, $acc0
    xor $acc1, $acc1

    ########################################################################
    # Multiply by b[2]

    mov	%rax, $t1
    mulq	8*0($a_ptr)
    add	%rax, $acc2
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*1($a_ptr)
    add	$t0, $acc3
    adc	\$0, %rdx
    add	%rax, $acc3
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*2($a_ptr)
    add	$t0, $acc4
    adc	\$0, %rdx
    add	%rax, $acc4
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*3($a_ptr)
    add	$t0, $acc5
    adc	\$0, %rdx
    add	%rax, $acc5
     mov	$acc2, %rax
    adc	%rdx, $acc0
    adc	\$0, $acc1

    ########################################################################
    # Third reduction step

    mov $acc2, $t1
    mulq $poly3       # rax = poly3 * rax mod 2^64
    add %rax, $acc0
    # mov	.LONE_mont+8*0(%rip),$poly1
    adc \$0, $acc1
    mulq $poly1
    sub	%rax, $acc2
    sbb	%rdx, $acc3
    sbb	\$0, $acc4
    mov	8*3($b_ptr), %rax
    sbb	\$0, $acc5
    sbb	\$0, $acc0
    sbb \$0, $acc1
    xor $acc2, $acc2

    ########################################################################
    # Multiply by b[3]

    mov	%rax, $t1
    mulq	8*0($a_ptr)
    add	%rax, $acc3
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*1($a_ptr)
    add	$t0, $acc4
    adc	\$0, %rdx
    add	%rax, $acc4
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*2($a_ptr)
    add	$t0, $acc5
    adc	\$0, %rdx
    add	%rax, $acc5
    mov	$t1, %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	8*3($a_ptr)
    add	$t0, $acc0
    adc	\$0, %rdx
    add	%rax, $acc0
     mov	$acc3, %rax
    adc	%rdx, $acc1
    adc	\$0, $acc2

    ########################################################################
    # Final reduction step

    mov $acc3, $t1
    mulq $poly3       # rax = poly3 * rax mod 2^64
    add %rax, $acc1
    adc \$0, $acc2
    mulq $poly1
    sub	%rax, $acc3
    sbb	%rdx, $acc4
    sbb	\$0, $acc5
    # mov	8*1($b_ptr), %rax
    sbb	\$0, $acc0
     mov	$acc4, $t0
    sbb	\$0, $acc1
    sbb \$0, $acc2

    mov	$acc5, $t1

    ########################################################################
    # Branch-less conditional subtraction of P

    sub	.Lpoly+8*0(%rip), $acc4
     mov	$acc0, $t2
    sbb	.Lpoly+8*1(%rip), $acc5
    sbb	.Lpoly+8*2(%rip), $acc0
     mov	$acc1, $t3
    sbb	.Lpoly+8*3(%rip), $acc1
    sbb	\$0, $acc2

    cmovc	$t0, $acc4
    cmovc	$t1, $acc5
    mov	$acc4, 8*0($r_ptr)
    cmovc	$t2, $acc0
    mov	$acc5, 8*1($r_ptr)
    cmovc	$t3, $acc1
    mov	$acc0, 8*2($r_ptr)
    mov	$acc1, 8*3($r_ptr)

    ret
.size	__secp256k1_mul_montq,.-__secp256k1_mul_montq

################################################################################
# void secp256k1_sqr_mont(
#   uint64_t res[4],
#   uint64_t a[4]);

# we optimize the square according to S.Gueron and V.Krasnov,
# "Speeding up Big-Number Squaring"
.globl	secp256k1_sqr_mont
.type	secp256k1_sqr_mont,\@function,2
.align	32
secp256k1_sqr_mont:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx
    and	cpu_info+8(%rip), %ecx
___
$code.=<<___;
    push	%rbp
    push	%rbx
    push	%r12
    push	%r13
    push	%r14
    push	%r15
___
$code.=<<___	if ($addx);
    cmp	\$0x80100, %ecx
    je	.Lsqr_montx
___
$code.=<<___;
    mov	8*0($a_ptr), %rax
    mov	8*1($a_ptr), $acc6
    mov	8*2($a_ptr), $acc7
    mov	8*3($a_ptr), $acc0

    call	__secp256k1_sqr_montq
___
$code.=<<___	if ($addx);
    jmp	.Lsqr_mont_done

.align	32
.Lsqr_montx:
    mov	8*0($a_ptr), %rdx
    mov	8*1($a_ptr), $acc6
    mov	8*2($a_ptr), $acc7
    mov	8*3($a_ptr), $acc0
    lea	-128($a_ptr), $a_ptr	# control u-op density

    call	__secp256k1_sqr_montx
___
$code.=<<___;
.Lsqr_mont_done:
    pop	%r15
    pop	%r14
    pop	%r13
    pop	%r12
    pop	%rbx
    pop	%rbp
    ret
.size	secp256k1_sqr_mont,.-secp256k1_sqr_mont

.type	__secp256k1_sqr_montq,\@abi-omnipotent
.align	32
__secp256k1_sqr_montq:
    mov	%rax, $acc5
    mulq	$acc6			# a[1]*a[0]
    mov	%rax, $acc1
    mov	$acc7, %rax
    mov	%rdx, $acc2

    mulq	$acc5			# a[0]*a[2]
    add	%rax, $acc2
    mov	$acc0, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc3

    mulq	$acc5			# a[0]*a[3]
    add	%rax, $acc3
     mov	$acc7, %rax
    adc	\$0, %rdx
    mov	%rdx, $acc4

    #################################
    mulq	$acc6			# a[1]*a[2]
    add	%rax, $acc3
    mov	$acc0, %rax
    adc	\$0, %rdx
    mov	%rdx, $t1

    mulq	$acc6			# a[1]*a[3]
    add	%rax, $acc4
     mov	$acc0, %rax
    adc	\$0, %rdx
    add	$t1, $acc4
    mov	%rdx, $acc5
    adc	\$0, $acc5

    #################################
    mulq	$acc7			# a[2]*a[3]
    xor	$acc7, $acc7
    add	%rax, $acc5
     mov	8*0($a_ptr), %rax
    mov	%rdx, $acc6
    adc	\$0, $acc6

    add	$acc1, $acc1		# acc1:6<<1
    adc	$acc2, $acc2
    adc	$acc3, $acc3
    adc	$acc4, $acc4
    adc	$acc5, $acc5
    adc	$acc6, $acc6
    adc	\$0, $acc7

    mulq	%rax
    mov	%rax, $acc0
    mov	8*1($a_ptr), %rax
    mov	%rdx, $t0

    mulq	%rax
    add	$t0, $acc1
    adc	%rax, $acc2
    mov	8*2($a_ptr), %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	%rax
    add	$t0, $acc3
    adc	%rax, $acc4
    mov	8*3($a_ptr), %rax
    adc	\$0, %rdx
    mov	%rdx, $t0

    mulq	%rax
    add	$t0, $acc5
    adc	%rax, $acc6
     mov	$acc0, %rax
    adc	%rdx, $acc7

    mov	.LK+8*0(%rip), $a_ptr
    mov	.LONE_mont+8*0(%rip), $t1

    ##########################################
    # Now the reduction
    # First iteration

    mov $acc0, %rax
    mulq $a_ptr
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc0
    sbb %rdx, $acc1
    sbb \$0, $acc2
    mov $t0, $acc0
    sbb \$0, $acc3
    sbb \$0, $acc0

    ##########################################
    # Second iteration

    mov $acc1, %rax
    mulq $a_ptr
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc1
    sbb %rdx, $acc2
    sbb \$0, $acc3
    mov $t0, $acc1
    sbb \$0, $acc2
    sbb \$0, $acc1

    ##########################################
    # Third iteration

    mov $acc2, %rax
    mulq $a_ptr
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc2
    sbb %rdx, $acc3
    sbb \$0, $acc0
    mov $t0, $acc2
    sbb \$0, $acc3
    sbb \$0, $acc2

    ###########################################
    # Last iteration

    mov $acc3, %rax
    mulq $a_ptr
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc3
    sbb %rdx, $acc0
    sbb \$0, $acc1
    mov $t0, $acc3
    sbb \$0, $acc0
    sbb \$0, $acc3

    mov	$acc3, %rdx
    xor	$acc3, $acc3

    ############################################
    # Add the rest of the acc
    add	$acc0, $acc4
    adc	$acc1, $acc5
     mov	$acc4, $acc0
    adc	$acc2, $acc6
    adc	%rdx, $acc7
     mov	$acc5, $acc1
    adc	\$0, $acc3

    sub	.Lpoly+8*0(%rip), $acc4	# .Lpoly[0]
     mov	$acc6, $acc2
    sbb	.Lpoly+8*1(%rip), $acc5	# .Lpoly[1]
    sbb	.Lpoly+8*2(%rip), $acc6	# .Lpoly[2]
     mov	$acc7, $t0
    sbb	.Lpoly+8*3(%rip), $acc7	# .Lpoly[3]
    sbb	\$0, $acc3

    cmovc	$acc0, $acc4
    cmovc	$acc1, $acc5
    mov	$acc4, 8*0($r_ptr)
    cmovc	$acc2, $acc6
    mov	$acc5, 8*1($r_ptr)
    cmovc	$t0, $acc7
    mov	$acc6, 8*2($r_ptr)
    mov	$acc7, 8*3($r_ptr)

    ret
.size	__secp256k1_sqr_montq,.-__secp256k1_sqr_montq
___

if ($addx) {
$code.=<<___;
.type	__secp256k1_mul_montx,\@abi-omnipotent
.align	32
__secp256k1_mul_montx:
    ########################################################################
    # Multiply by b[0]

    mov	.LK+8*0(%rip), $t4

    mulx	$acc1, $acc0, $acc1
    mulx	$acc2, $t0, $acc2
    xor	$acc5, $acc5		# cf=0
    mulx	$acc3, $t1, $acc3
    adc	$t0, $acc1
    mulx	$acc4, $t0, $acc4
     mov	.LONE_mont+8*0(%rip), $poly1
    adc	$t1, $acc2
     mov     $t4, %rdx
    adc	$t0, $acc3
     mulx    $acc0, $t0, $t1
     mov     $poly1, %rdx
    adc	\$0, $acc4
     mulx    $t0, $acc7, $t1

    ########################################################################
    # First reduction step
    xor     $acc5, $acc5
    adox    $t0, $acc4
    adox    $acc5, $acc5
    xor	    $acc0, $acc0 		# $acc0=0,cf=0,of=0
    sbb     $t1, $acc1
    sbb     \$0, $acc2
    sbb     \$0, $acc3
    sbb     \$0, $acc4
    sbb     \$0, $acc5
    # xor	$acc0, $acc0 		# $acc0=0,cf=0,of=0
    mov	8*1($b_ptr), %rdx

    ########################################################################
    # Multiply by b[1]
    # (acc0,acc5,acc4,acc3,acc2,acc1) = (acc5,acc4,acc3,acc2,acc1) + a * b[1]

    mulx	8*0+128($a_ptr), $t0, $t1
    adcx	$t0, $acc1
    adox	$t1, $acc2

    mulx	8*1+128($a_ptr), $t0, $t1
    adcx	$t0, $acc2
    adox	$t1, $acc3

    mulx	8*2+128($a_ptr), $t0, $t1
    adcx	$t0, $acc3
    adox	$t1, $acc4

    mulx	8*3+128($a_ptr), $t0, $t1
     mov     $t4, %rdx
    adcx	$t0, $acc4
    adox	$t1, $acc5

     mulx    $acc1, $t0, $t1
    adcx	$acc0, $acc5
    adox	$acc0, $acc0
     mov     $poly1, %rdx
    adc	\$0, $acc0
     mulx    $t0, $acc7, $t1

    ########################################################################
    # Second reduction step

    xor	%rdx, %rdx
    adox    $t0, $acc5
    adox    %rdx, $acc0
    xor	    $acc1, $acc1		# $acc1=0,cf=0,of=0
    sbb     $t1, $acc2
    sbb     \$0, $acc3
    sbb     \$0, $acc4
    sbb     \$0, $acc5
    sbb     \$0, $acc0
    mov    8*2($b_ptr), %rdx
    # xor	$acc1, $acc1		# $acc1=0,cf=0,of=0

    ########################################################################
    # Multiply by b[2]

    mulx	8*0+128($a_ptr), $t0, $t1
    adcx	$t0, $acc2
    adox	$t1, $acc3

    mulx	8*1+128($a_ptr), $t0, $t1
    adcx	$t0, $acc3
    adox	$t1, $acc4

    mulx	8*2+128($a_ptr), $t0, $t1
    adcx	$t0, $acc4
    adox	$t1, $acc5

    mulx	8*3+128($a_ptr), $t0, $t1
     mov	$t4, %rdx
    adcx	$t0, $acc5
    adox	$t1, $acc0

     mulx    $acc2, $t0, $t1
    adcx	$acc1, $acc0
    adox	$acc1, $acc1
     mov     $poly1, %rdx
    adc	\$0, $acc1
     mulx    $t0, $acc7, $t1

    ########################################################################
    # Third reduction step

    xor	%rdx, %rdx
    adox    $t0, $acc0
    adox    %rdx, $acc1
    xor	    $acc2, $acc2		# $acc2=0,cf=0,of=0
    sbb     $t1, $acc3
    sbb     \$0, $acc4
    sbb     \$0, $acc5
    sbb     \$0, $acc0
    sbb     \$0, $acc1

    mov    8*3($b_ptr), %rdx
    # xor	$acc2, $acc2		# $acc2=0,cf=0,of=0

    ########################################################################
    # Multiply by b[3]
    mulx	8*0+128($a_ptr), $t0, $t1
    adcx	$t0, $acc3
    adox	$t1, $acc4

    mulx	8*1+128($a_ptr), $t0, $t1
    adcx	$t0, $acc4
    adox	$t1, $acc5

    mulx	8*2+128($a_ptr), $t0, $t1
    adcx	$t0, $acc5
    adox	$t1, $acc0

    mulx	8*3+128($a_ptr), $t0, $t1
     mov	 $t4, %rdx
    adcx	$t0, $acc0
    adox	$t1, $acc1

     mulx    $acc3, $t0, $t1
    adcx	$acc2, $acc1
    adox	$acc2, $acc2
     mov     $poly1, %rdx
    adc	\$0, $acc2
     mulx    $t0, $acc7, $t1

    ########################################################################
    # Fourth reduction step

    xor	%rdx, %rdx
    adox    $t0, $acc1
    adox    %rdx, $acc2
    xor	    $acc3, $acc3		# $acc3=0,cf=0,of=0
    sbb     $t1, $acc4
    sbb     \$0, $acc5
    sbb     \$0, $acc0
    sbb     \$0, $acc1
    sbb     \$0, $acc2

    # xor	$acc3, $acc3		# $acc3=0,cf=0,of=0
    mov	$acc4, $t2
    mov	$acc5, $t3

    ########################################################################
    # Branch-less conditional subtraction of P
    xor	%eax, %eax
     mov	$acc0, $t0

    sub	.Lpoly+8*0(%rip), $acc4	# .Lpoly[0]
    sbb	.Lpoly+8*1(%rip), $acc5	# .Lpoly[1]
    sbb	.Lpoly+8*2(%rip), $acc0	# .Lpoly[2]
     mov	$acc1, $t1
    sbb	.Lpoly+8*3(%rip), $acc1	# .Lpoly[3]
    sbb	\$0, $acc2

    cmovc	$t2, $acc4
    cmovc	$t3, $acc5
     mov	$acc4, 8*0($r_ptr)
    cmovc	$t0, $acc0
     mov	$acc5, 8*1($r_ptr)
    cmovc	$t1, $acc1
     mov	$acc0, 8*2($r_ptr)
     mov	$acc1, 8*3($r_ptr)

    ret
.size	__secp256k1_mul_montx,.-__secp256k1_mul_montx

.type	__secp256k1_sqr_montx,\@abi-omnipotent
.align	32
__secp256k1_sqr_montx:
    mulx	$acc6, $acc1, $acc2
    mulx	$acc7, $t0, $acc3
    xor	%eax, %eax
    adc	$t0, $acc2
    mulx	$acc0, $t1, $acc4
     mov	$acc6, %rdx
    adc	$t1, $acc3
    adc	\$0, $acc4
    xor	$acc5, $acc5		# $acc5=0,cf=0,of=0

    #################################
    mulx	$acc7, $t0, $t1
    adcx	$t0, $acc3
    adox	$t1, $acc4

    mulx	$acc0, $t0, $t1
     mov	$acc7, %rdx
    adcx	$t0, $acc4
    adox	$t1, $acc5
    adc	\$0, $acc5

    #################################
    mulx	$acc0, $t0, $acc6
     mov	8*0+128($a_ptr), %rdx
    xor	$acc7, $acc7		# $acc7=0,cf=0,of=0
     adcx	$acc1, $acc1		# acc1:6<<1
    adox	$t0, $acc5
     adcx	$acc2, $acc2
    adox	$acc7, $acc6		# of=0

    mulx	%rdx, $acc0, $t1
    mov	8*1+128($a_ptr), %rdx
     adcx	$acc3, $acc3
    adox	$t1, $acc1
     adcx	$acc4, $acc4
    mulx	%rdx, $t0, $t4
    mov	8*2+128($a_ptr), %rdx
     adcx	$acc5, $acc5
    adox	$t0, $acc2
     adcx	$acc6, $acc6
    .byte	0x67
    mulx	%rdx, $t0, $t1
    mov	8*3+128($a_ptr), %rdx
    adox	$t4, $acc3
     adcx	$acc7, $acc7
    adox	$t0, $acc4
    #  mov	\$32, $a_ptr
    adox	$t1, $acc5
    .byte	0x67,0x67
    mulx	%rdx, $t0, $t4
    adox	$t0, $acc6
    adox	$t4, $acc7

    # reduction step 1
    mov     \$0xd838091dd2253531, %rdx
    mulx    $acc0, $acc0, $t1
    mov     \$0x00000001000003d1, %rdx
    xor     $t4, $t4
    mulx    $acc0, $t0, $t1

    sbb     $t1, $acc1
    sbb     \$0, $acc2
    sbb     \$0, $acc3
    sbb     \$0, $acc0

    # reduction step 2
    mov     \$0xd838091dd2253531, %rdx
    mulx    $acc1, $acc1, $t1
    mov     \$0x00000001000003d1, %rdx
    xor     $t4, $t4
    mulx    $acc1, $t0, $t1

    sbb     $t1, $acc2
    sbb     \$0, $acc3
    sbb     \$0, $acc0
    sbb     \$0, $acc1

    # reduction step 3
    mov     \$0xd838091dd2253531, %rdx
    mulx    $acc2, $acc2, $t1
    mov     \$0x00000001000003d1, %rdx
    xor     $t4, $t4
    mulx    $acc2, $t0, $t1

    sbb     $t1, $acc3
    sbb     \$0, $acc0
    sbb     \$0, $acc1
    sbb     \$0, $acc2

    # reduction step 4
    mov     \$0xd838091dd2253531, %rdx
    mulx    $acc3, $acc3, $t1
    mov     \$0x00000001000003d1, %rdx
    xor     $t4, $t4
    mulx    $acc3, $t0, $t1

    sbb     $t1, $acc0
    sbb     \$0, $acc1
    sbb     \$0, $acc2
    sbb     \$0, $acc3

    ###########################
    xor	$t3, $t3		# cf=0
    add	$acc0, $acc4		# accumulate upper half
     mov	.Lpoly+8*1(%rip), $a_ptr
    adc	$acc1, $acc5
     mov	$acc4, $acc0
    adc	$acc2, $acc6
    adc	$acc3, $acc7
     mov	$acc5, $acc1
    adc	\$0, $t3

    xor	%eax, %eax		# cf=0
    sub	.Lpoly+8*0(%rip), $acc4	# .Lpoly[0]
     mov	$acc6, $acc2
    sbb	.Lpoly+8*1(%rip), $acc5	# .Lpoly[1]
    sbb	.Lpoly+8*2(%rip), $acc6	# .Lpoly[2]
     mov	$acc7, $acc3
    sbb	.Lpoly+8*3(%rip), $acc7	# .Lpoly[3]
    sbb	\$0, $t3

    cmovc	$acc0, $acc4
    cmovc	$acc1, $acc5
    mov	$acc4, 8*0($r_ptr)
    cmovc	$acc2, $acc6
    mov	$acc5, 8*1($r_ptr)
    cmovc	$acc3, $acc7
    mov	$acc6, 8*2($r_ptr)
    mov	$acc7, 8*3($r_ptr)

    ret
.size	__secp256k1_sqr_montx,.-__secp256k1_sqr_montx
___
}
}
{
my ($r_ptr,$in_ptr)=("%rdi","%rsi");
my ($acc0,$acc1,$acc2,$acc3)=map("%r$_",(8..11));
my ($t0,$t1,$t2)=("%rcx","%r12","%r13");

$code.=<<___;
################################################################################
# void secp256k1_from_mont(
#   uint64_t res[4],
#   uint64_t in[4]);
# This one performs Montgomery multiplication by 1, so we only need the reduction

.globl	secp256k1_from_mont
.type	secp256k1_from_mont,\@function,2
.align	32
secp256k1_from_mont:
    push	%r12
    push	%r13

    mov	8*0($in_ptr), $acc0
    mov	8*1($in_ptr), $acc1
    mov	8*2($in_ptr), $acc2
    mov	8*3($in_ptr), $acc3

    mov	.LK+8*0(%rip), $t2
    mov	.LONE_mont+8*0(%rip), $t1
    #########################################
    # First iteration

    mov $acc0, %rax
    mulq $t2
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc0
    sbb %rdx, $acc1
    sbb \$0, $acc2
    mov $t0, $acc0
    sbb \$0, $acc3
    sbb \$0, $acc0

    ##########################################
    # Second iteration

    mov $acc1, %rax
    mulq $t2
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc1
    sbb %rdx, $acc2
    sbb \$0, $acc3
    mov $t0, $acc1
    sbb \$0, $acc2
    sbb \$0, $acc1

    ##########################################
    # Third iteration

    mov $acc2, %rax
    mulq $t2
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc2
    sbb %rdx, $acc3
    sbb \$0, $acc0
    mov $t0, $acc2
    sbb \$0, $acc3
    sbb \$0, $acc2

    ###########################################
    # Last iteration

    mov $acc3, %rax
    mulq $t2
    mov %rax, $t0
    mulq $t1
    sub %rax, $acc3
    sbb %rdx, $acc0
    sbb \$0, $acc1
    mov $t0, $acc3
    sbb \$0, $acc0
    sbb \$0, $acc3
    # now we have (acc3, acc2, acc1, acc0)

    ###########################################
    # Branch-less conditional subtraction
    mov	$acc0, $t0
    mov	$acc1, $in_ptr
    mov	$acc2, %rax
    mov	$acc3, %rdx

    sub	.Lpoly+8*0(%rip), $acc0
    sbb	.Lpoly+8*1(%rip), $acc1
    sbb	.Lpoly+8*2(%rip), $acc2
    sbb	.Lpoly+8*3(%rip), $acc3
    sbb	$t2, $t2

    cmovnz	$t0, $acc0
    cmovnz	$in_ptr, $acc1
     mov	$acc0, 8*0($r_ptr)
    cmovnz	%rax, $acc2
     mov	$acc1, 8*1($r_ptr)
    cmovnz	%rdx, $acc3
     mov	$acc2, 8*2($r_ptr)
     mov	$acc3, 8*3($r_ptr)

    pop	%r13
    pop	%r12
    ret
.size	secp256k1_from_mont,.-secp256k1_from_mont
___
}
{
my ($val,$in_t,$index)=$win64?("%rcx","%rdx","%r8d"):("%rdi","%rsi","%edx");
my ($ONE,$INDEX,$Ra,$Rb,$Rc,$Rd,$Re,$Rf)=map("%xmm$_",(0..7));
my ($M0,$T0a,$T0b,$T0c,$T0d,$T0e,$T0f,$TMP0)=map("%xmm$_",(8..15));
my ($M1,$T2a,$T2b,$TMP2,$M2,$T2a,$T2b,$TMP2)=map("%xmm$_",(8..15));

$code.=<<___;
################################################################################
# void secp256k1_scatter_w5(uint64_t *val, uint64_t *in_t, int index);
.globl	secp256k1_scatter_w5
.type	secp256k1_scatter_w5,\@abi-omnipotent
.align	32
secp256k1_scatter_w5:
    lea	-3($index,$index,2), $index
    movdqa	0x00($in_t), %xmm0
    shl	\$5, $index
    movdqa	0x10($in_t), %xmm1
    movdqa	0x20($in_t), %xmm2
    movdqa	0x30($in_t), %xmm3
    movdqa	0x40($in_t), %xmm4
    movdqa	0x50($in_t), %xmm5
    movdqa	%xmm0, 0x00($val,$index)
    movdqa	%xmm1, 0x10($val,$index)
    movdqa	%xmm2, 0x20($val,$index)
    movdqa	%xmm3, 0x30($val,$index)
    movdqa	%xmm4, 0x40($val,$index)
    movdqa	%xmm5, 0x50($val,$index)

    ret
.size	secp256k1_scatter_w5,.-secp256k1_scatter_w5

################################################################################
# void secp256k1_scatter_w7(uint64_t *val, uint64_t *in_t, int index);
.globl	secp256k1_scatter_w7
.type	secp256k1_scatter_w7,\@abi-omnipotent
.align	32
secp256k1_scatter_w7:
    movdqu	0x00($in_t), %xmm0
    shl	\$6, $index
    movdqu	0x10($in_t), %xmm1
    movdqu	0x20($in_t), %xmm2
    movdqu	0x30($in_t), %xmm3
    movdqa	%xmm0, 0x00($val,$index)
    movdqa	%xmm1, 0x10($val,$index)
    movdqa	%xmm2, 0x20($val,$index)
    movdqa	%xmm3, 0x30($val,$index)

    ret
.size	secp256k1_scatter_w7,.-secp256k1_scatter_w7
___
}
{{{
########################################################################
# This block implements higher level point_double, point_add and
# point_add_affine. The key to performance in this case is to allow
# out-of-order execution logic to overlap computations from next step
# with tail processing from current step. By using tailored calling
# sequence we minimize inter-step overhead to give processor better
# shot at overlapping operations...
#
# You will notice that input data is copied to stack. Trouble is that
# there are no registers to spare for holding original pointers and
# reloading them, pointers, would create undesired dependencies on
# effective addresses calculation paths. In other words it's too done
# to favour out-of-order execution logic.
#						<appro@openssl.org>

my ($r_ptr,$a_ptr,$b_org,$b_ptr)=("%rdi","%rsi","%rdx","%rbx");
my ($acc0,$acc1,$acc2,$acc3,$acc4,$acc5,$acc6,$acc7)=map("%r$_",(8..15));
my ($t0,$t1,$t2,$t3,$t4)=("%rax","%rbp","%rcx",$acc4,$acc4);
my ($poly1,$poly3)=($acc6,$acc7);

sub load_for_mul () {
my ($a,$b,$src0) = @_;
my $bias = $src0 eq "%rax" ? 0 : -128;

"	mov	$b, $src0
    lea	$b, $b_ptr
    mov	8*0+$a, $acc1
    mov	8*1+$a, $acc2
    lea	$bias+$a, $a_ptr
    mov	8*2+$a, $acc3
    mov	8*3+$a, $acc4"
}

sub load_for_sqr () {
my ($a,$src0) = @_;
my $bias = $src0 eq "%rax" ? 0 : -128;

"	mov	8*0+$a, $src0
    mov	8*1+$a, $acc6
    lea	$bias+$a, $a_ptr
    mov	8*2+$a, $acc7
    mov	8*3+$a, $acc0"
}

                                    {
########################################################################
# operate in 4-5-0-1 "name space" that matches multiplication output
#
my ($a0,$a1,$a2,$a3,$t3,$t4)=($acc4,$acc5,$acc0,$acc1,$acc2,$acc3);

$code.=<<___;
.type	__secp256k1_add_toq,\@abi-omnipotent
.align	32
__secp256k1_add_toq:
    xor	$t4,$t4
    add	8*0($b_ptr), $a0
    adc	8*1($b_ptr), $a1
     mov	$a0, $t0
    adc	8*2($b_ptr), $a2
    adc	8*3($b_ptr), $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_add_toq,.-__secp256k1_add_toq

.type	__secp256k1_sub_fromq,\@abi-omnipotent
.align	32
__secp256k1_sub_fromq:
    sub	8*0($b_ptr), $a0
    sbb	8*1($b_ptr), $a1
     mov	$a0, $t0
    sbb	8*2($b_ptr), $a2
    sbb	8*3($b_ptr), $a3
     mov	$a1, $t1
    sbb	$t4, $t4

    add	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    adc	.Lpoly+8*1(%rip), $a1
    adc	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    adc	.Lpoly+8*3(%rip), $a3
    test	$t4, $t4

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovz	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovz	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_sub_fromq,.-__secp256k1_sub_fromq

.type	__secp256k1_subq,\@abi-omnipotent
.align	32
__secp256k1_subq:
    sub	$a0, $t0
    sbb	$a1, $t1
     mov	$t0, $a0
    sbb	$a2, $t2
    sbb	$a3, $t3
     mov	$t1, $a1
    sbb	$t4, $t4

    add	.Lpoly+8*0(%rip), $t0
     mov	$t2, $a2
    adc	.Lpoly+8*1(%rip), $t1
    adc	.Lpoly+8*2(%rip), $t2
     mov	$t3, $a3
    adc	.Lpoly+8*3(%rip), $t3
    test	$t4, $t4

    cmovnz	$t0, $a0
    cmovnz	$t1, $a1
    cmovnz	$t2, $a2
    cmovnz	$t3, $a3

    ret
.size	__secp256k1_subq,.-__secp256k1_subq

.type	__secp256k1_mul_by_2q,\@abi-omnipotent
.align	32
__secp256k1_mul_by_2q:
    xor	$t4, $t4
    add	$a0, $a0		# a0:a3+a0:a3
    adc	$a1, $a1
     mov	$a0, $t0
    adc	$a2, $a2
    adc	$a3, $a3
     mov	$a1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_mul_by_2q,.-__secp256k1_mul_by_2q
___
                                    }
sub gen_double () {
    my $x = shift;
    my ($src0,$sfx,$bias);
    my ($S,$M,$Zsqr,$in_x,$tmp0)=map(32*$_,(0..4));

    if ($x ne "x") {
    $src0 = "%rax";
    $sfx  = "";
    $bias = 0;

$code.=<<___;
.globl	secp256k1_point_dbl
.type	secp256k1_point_dbl,\@function,2
.align	32
secp256k1_point_dbl:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx
    and	cpu_info+8(%rip), %ecx
    cmp	\$0x80100, %ecx
    je	.Lpoint_doublex
___
    } else {
    $src0 = "%rdx";
    $sfx  = "x";
    $bias = 128;

$code.=<<___;
.type	secp256k1_point_dblx,\@function,2
.align	32
secp256k1_point_dblx:
.Lpoint_doublex:
___
    }
$code.=<<___;
    push	%rbp
    push	%rbx
    push	%r12
    push	%r13
    push	%r14
    push	%r15
    sub	\$32*5+8, %rsp

.Lpoint_double_shortcut$x:
    movdqu	0x00($a_ptr), %xmm0		# copy	*(POINT256 *)$a_ptr.x
    mov	$a_ptr, $b_ptr			# backup copy
    movdqu	0x10($a_ptr), %xmm1
     mov	0x20+8*0($a_ptr), $acc4		# load in_y in "5-4-0-1" order
     mov	0x20+8*1($a_ptr), $acc5
     mov	0x20+8*2($a_ptr), $acc0
     mov	0x20+8*3($a_ptr), $acc1
     mov	.Lpoly+8*1(%rip), $poly1
     mov	.Lpoly+8*3(%rip), $poly3
    movdqa	%xmm0, $in_x(%rsp)
    movdqa	%xmm1, $in_x+0x10(%rsp)
    lea	0x20($r_ptr), $acc2
    lea	0x40($r_ptr), $acc3
    movq	$r_ptr, %xmm0
    movq	$acc2, %xmm1
    movq	$acc3, %xmm2

    lea	$S(%rsp), $r_ptr
    call	__secp256k1_mul_by_2$x	# p256_mul_by_2(S, in_y);

    `&load_for_sqr("$S(%rsp)", "$src0")`
    lea	$S(%rsp), $r_ptr
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(S, S);

    mov	0x20($b_ptr), $src0		# $b_ptr is still valid
    mov	0x40+8*0($b_ptr), $acc1
    mov	0x40+8*1($b_ptr), $acc2
    mov	0x40+8*2($b_ptr), $acc3
    mov	0x40+8*3($b_ptr), $acc4
    lea	0x40-$bias($b_ptr), $a_ptr
    lea	0x20($b_ptr), $b_ptr
    movq	%xmm2, $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(res_z, in_z, in_y);
    call	__secp256k1_mul_by_2$x	# p256_mul_by_2(res_z, res_z);

    `&load_for_sqr("$in_x(%rsp)", "$src0")`
    lea	$M(%rsp), $r_ptr
    call    __secp256k1_sqr_mont$x	# p256_sqr_mont(M, in_x);
    mov $acc6, $acc0
    mov $acc7, $acc1
    lea	$tmp0(%rsp), $r_ptr
    call	__secp256k1_mul_by_2$x
    lea	$M(%rsp), $b_ptr
    lea	$M(%rsp), $r_ptr
    call	__secp256k1_add_to$x		# p256_mul_by_3(M, M);

    `&load_for_sqr("$S(%rsp)", "$src0")`
    movq	%xmm1, $r_ptr
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(res_y, S);
___
{
######## secp256k1_div_by_2(res_y, res_y); ##########################
# operate in 4-5-6-7 "name space" that matches squaring output
#
my ($poly1,$poly3)=($a_ptr,$t1);
my ($a0,$a1,$a2,$a3,$t3,$t4,$t1)=($acc4,$acc5,$acc6,$acc7,$acc0,$acc1,$acc2);

$code.=<<___;
    xor	$t4, $t4
    mov	$a0, $t0
    add	.Lpoly+8*0(%rip), $a0
    mov	$a1, $t1
    adc	.Lpoly+8*1(%rip), $a1
    mov	$a2, $t2
    adc	.Lpoly+8*2(%rip), $a2
    mov	$a3, $t3
    adc	.Lpoly+8*3(%rip), $a3
    adc	\$0, $t4
    xor	$a_ptr, $a_ptr		# borrow $a_ptr
    test	\$1, $t0

    cmovz	$t0, $a0
    cmovz	$t1, $a1
    cmovz	$t2, $a2
    cmovz	$t3, $a3
    cmovz	$a_ptr, $t4

    mov	$a1, $t0		# a0:a3>>1
    shr	\$1, $a0
    shl	\$63, $t0
    mov	$a2, $t1
    shr	\$1, $a1
    or	$t0, $a0
    shl	\$63, $t1
    mov	$a3, $t2
    shr	\$1, $a2
    or	$t1, $a1
    shl	\$63, $t2
    mov	$a0, 8*0($r_ptr)
    shr	\$1, $a3
    mov	$a1, 8*1($r_ptr)
    shl	\$63, $t4
    or	$t2, $a2
    or	$t4, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)
___
}
$code.=<<___;
    `&load_for_mul("$S(%rsp)", "$in_x(%rsp)", "$src0")`
    lea	$S(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S, S, in_x);

    lea	$tmp0(%rsp), $r_ptr
    call	__secp256k1_mul_by_2$x	# p256_mul_by_2(tmp0, S);

    `&load_for_sqr("$M(%rsp)", "$src0")`
    movq	%xmm0, $r_ptr
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(res_x, M);

    lea	$tmp0(%rsp), $b_ptr
    mov	$acc6, $acc0			# harmonize sqr output and sub input
    mov	$acc7, $acc1
    mov	$a_ptr, $poly1
    mov	$t1, $poly3
    call	__secp256k1_sub_from$x	# p256_sub(res_x, res_x, tmp0);

    mov	$S+8*0(%rsp), $t0
    mov	$S+8*1(%rsp), $t1
    mov	$S+8*2(%rsp), $t2
    mov	$S+8*3(%rsp), $acc2		# "4-5-0-1" order
    lea	$S(%rsp), $r_ptr
    call	__secp256k1_sub$x		# p256_sub(S, S, res_x);

    mov	$M(%rsp), $src0
    lea	$M(%rsp), $b_ptr
    mov	$acc4, $acc6			# harmonize sub output and mul input
    xor	%ecx, %ecx
    mov	$acc4, $S+8*0(%rsp)		# have to save:-(
    mov	$acc5, $acc2
    mov	$acc5, $S+8*1(%rsp)
    cmovz	$acc0, $acc3
    mov	$acc0, $S+8*2(%rsp)
    lea	$S-$bias(%rsp), $a_ptr
    cmovz	$acc1, $acc4
    mov	$acc1, $S+8*3(%rsp)
    mov	$acc6, $acc1
    lea	$S(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S, S, M);

    movq	%xmm1, $b_ptr
    movq	%xmm1, $r_ptr
    call	__secp256k1_sub_from$x	# p256_sub(res_y, S, res_y);

    add	\$32*5+8, %rsp
    pop	%r15
    pop	%r14
    pop	%r13
    pop	%r12
    pop	%rbx
    pop	%rbp
    ret
.size	secp256k1_point_dbl$sfx,.-secp256k1_point_dbl$sfx
___
}
&gen_double("q");

sub gen_add () {
    my $x = shift;
    my ($src0,$sfx,$bias);
    my ($H,$Hsqr,$R,$Rsqr,$Hcub,
    $U1,$U2,$S1,$S2,
    $res_x,$res_y,$res_z,
    $in1_x,$in1_y,$in1_z,
    $in2_x,$in2_y,$in2_z)=map(32*$_,(0..17));
    my ($Z1sqr, $Z2sqr) = ($Hsqr, $Rsqr);

    if ($x ne "x") {
    $src0 = "%rax";
    $sfx  = "";
    $bias = 0;

$code.=<<___;
.globl	secp256k1_point_add
.type	secp256k1_point_add,\@function,3
.align	32
secp256k1_point_add:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx
    and	cpu_info+8(%rip), %ecx
    cmp	\$0x80100, %ecx
    je	.Lpoint_addx
___
    } else {
    $src0 = "%rdx";
    $sfx  = "x";
    $bias = 128;

$code.=<<___;
.type	secp256k1_point_addx,\@function,3
.align	32
secp256k1_point_addx:
.Lpoint_addx:
___
    }
$code.=<<___;
    push	%rbp
    push	%rbx
    push	%r12
    push	%r13
    push	%r14
    push	%r15
    sub	\$32*18+8, %rsp

    movdqu	0x00($a_ptr), %xmm0		# copy	*(POINT256 *)$a_ptr
    movdqu	0x10($a_ptr), %xmm1
    movdqu	0x20($a_ptr), %xmm2
    movdqu	0x30($a_ptr), %xmm3
    movdqu	0x40($a_ptr), %xmm4
    movdqu	0x50($a_ptr), %xmm5
    mov	$a_ptr, $b_ptr			# reassign
    mov	$b_org, $a_ptr			# reassign
    movdqa	%xmm0, $in1_x(%rsp)
    movdqa	%xmm1, $in1_x+0x10(%rsp)
    movdqa	%xmm2, $in1_y(%rsp)
    movdqa	%xmm3, $in1_y+0x10(%rsp)
    movdqa	%xmm4, $in1_z(%rsp)
    movdqa	%xmm5, $in1_z+0x10(%rsp)
    por	%xmm4, %xmm5

    movdqu	0x00($a_ptr), %xmm0		# copy	*(POINT256 *)$b_ptr
     pshufd	\$0xb1, %xmm5, %xmm3
    movdqu	0x10($a_ptr), %xmm1
    movdqu	0x20($a_ptr), %xmm2
     por	%xmm3, %xmm5
    movdqu	0x30($a_ptr), %xmm3
     mov	0x40+8*0($a_ptr), $src0		# load original in2_z
     mov	0x40+8*1($a_ptr), $acc6
     mov	0x40+8*2($a_ptr), $acc7
     mov	0x40+8*3($a_ptr), $acc0
    movdqa	%xmm0, $in2_x(%rsp)
     pshufd	\$0x1e, %xmm5, %xmm4
    movdqa	%xmm1, $in2_x+0x10(%rsp)
    movdqu	0x40($a_ptr),%xmm0		# in2_z again
    movdqu	0x50($a_ptr),%xmm1
    movdqa	%xmm2, $in2_y(%rsp)
    movdqa	%xmm3, $in2_y+0x10(%rsp)
     por	%xmm4, %xmm5
     pxor	%xmm4, %xmm4
    por	%xmm0, %xmm1
     movq	$r_ptr, %xmm0			# save $r_ptr

    lea	0x40-$bias($a_ptr), $a_ptr	# $a_ptr is still valid
     mov	$src0, $in2_z+8*0(%rsp)		# make in2_z copy
     mov	$acc6, $in2_z+8*1(%rsp)
     mov	$acc7, $in2_z+8*2(%rsp)
     mov	$acc0, $in2_z+8*3(%rsp)
    lea	$Z2sqr(%rsp), $r_ptr		# Z2^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Z2sqr, in2_z);

    pcmpeqd	%xmm4, %xmm5
    pshufd	\$0xb1, %xmm1, %xmm4
    por	%xmm1, %xmm4
    pshufd	\$0, %xmm5, %xmm5		# in1infty
    pshufd	\$0x1e, %xmm4, %xmm3
    por	%xmm3, %xmm4
    pxor	%xmm3, %xmm3
    pcmpeqd	%xmm3, %xmm4
    pshufd	\$0, %xmm4, %xmm4		# in2infty
     mov	0x40+8*0($b_ptr), $src0		# load original in1_z
     mov	0x40+8*1($b_ptr), $acc6
     mov	0x40+8*2($b_ptr), $acc7
     mov	0x40+8*3($b_ptr), $acc0
    movq	$b_ptr, %xmm1

    lea	0x40-$bias($b_ptr), $a_ptr
    lea	$Z1sqr(%rsp), $r_ptr		# Z1^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Z1sqr, in1_z);

    `&load_for_mul("$Z2sqr(%rsp)", "$in2_z(%rsp)", "$src0")`
    lea	$S1(%rsp), $r_ptr		# S1 = Z2^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S1, Z2sqr, in2_z);

    `&load_for_mul("$Z1sqr(%rsp)", "$in1_z(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr		# S2 = Z1^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, Z1sqr, in1_z);

    `&load_for_mul("$S1(%rsp)", "$in1_y(%rsp)", "$src0")`
    lea	$S1(%rsp), $r_ptr		# S1 = Y1*Z2^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S1, S1, in1_y);

    `&load_for_mul("$S2(%rsp)", "$in2_y(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr		# S2 = Y2*Z1^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, S2, in2_y);

    lea	$S1(%rsp), $b_ptr
    lea	$R(%rsp), $r_ptr		# R = S2 - S1
    call	__secp256k1_sub_from$x	# p256_sub(R, S2, S1);

    or	$acc5, $acc4			# see if result is zero
    movdqa	%xmm4, %xmm2
    or	$acc0, $acc4
    or	$acc1, $acc4
    por	%xmm5, %xmm2			# in1infty || in2infty
    movq	$acc4, %xmm3

    `&load_for_mul("$Z2sqr(%rsp)", "$in1_x(%rsp)", "$src0")`
    lea	$U1(%rsp), $r_ptr		# U1 = X1*Z2^2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(U1, in1_x, Z2sqr);

    `&load_for_mul("$Z1sqr(%rsp)", "$in2_x(%rsp)", "$src0")`
    lea	$U2(%rsp), $r_ptr		# U2 = X2*Z1^2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(U2, in2_x, Z1sqr);

    lea	$U1(%rsp), $b_ptr
    lea	$H(%rsp), $r_ptr		# H = U2 - U1
    call	__secp256k1_sub_from$x	# p256_sub(H, U2, U1);

    or	$acc5, $acc4			# see if result is zero
    or	$acc0, $acc4
    or	$acc1, $acc4

    .byte	0x3e				# predict taken
    jnz	.Ladd_proceed$x			# is_equal(U1,U2)?
    movq	%xmm2, $acc0
    movq	%xmm3, $acc1
    test	$acc0, $acc0
    jnz	.Ladd_proceed$x			# (in1infty || in2infty)?
    test	$acc1, $acc1
    jz	.Ladd_double$x			# is_equal(S1,S2)?

    movq	%xmm0, $r_ptr			# restore $r_ptr
    pxor	%xmm0, %xmm0
    movdqu	%xmm0, 0x00($r_ptr)
    movdqu	%xmm0, 0x10($r_ptr)
    movdqu	%xmm0, 0x20($r_ptr)
    movdqu	%xmm0, 0x30($r_ptr)
    movdqu	%xmm0, 0x40($r_ptr)
    movdqu	%xmm0, 0x50($r_ptr)
    jmp	.Ladd_done$x

.align	32
.Ladd_double$x:
    movq	%xmm1, $a_ptr			# restore $a_ptr
    movq	%xmm0, $r_ptr			# restore $r_ptr
    add	\$`32*(18-5)`, %rsp		# difference in frame sizes
    jmp	.Lpoint_double_shortcut$x

.align	32
.Ladd_proceed$x:
    `&load_for_sqr("$R(%rsp)", "$src0")`
    lea	$Rsqr(%rsp), $r_ptr		# R^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Rsqr, R);

    `&load_for_mul("$H(%rsp)", "$in1_z(%rsp)", "$src0")`
    lea	$res_z(%rsp), $r_ptr		# Z3 = H*Z1*Z2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(res_z, H, in1_z);

    `&load_for_sqr("$H(%rsp)", "$src0")`
    lea	$Hsqr(%rsp), $r_ptr		# H^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Hsqr, H);

    `&load_for_mul("$res_z(%rsp)", "$in2_z(%rsp)", "$src0")`
    lea	$res_z(%rsp), $r_ptr		# Z3 = H*Z1*Z2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(res_z, res_z, in2_z);

    `&load_for_mul("$Hsqr(%rsp)", "$H(%rsp)", "$src0")`
    lea	$Hcub(%rsp), $r_ptr		# H^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(Hcub, Hsqr, H);

    `&load_for_mul("$Hsqr(%rsp)", "$U1(%rsp)", "$src0")`
    lea	$U2(%rsp), $r_ptr		# U1*H^2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(U2, U1, Hsqr);
___
{
#######################################################################
# operate in 4-5-0-1 "name space" that matches multiplication output
#
my ($acc0,$acc1,$acc2,$acc3,$t3,$t4)=($acc4,$acc5,$acc0,$acc1,$acc2,$acc3);
my ($poly1, $poly3)=($acc6,$acc7);

$code.=<<___;
    #lea	$U2(%rsp), $a_ptr
    #lea	$Hsqr(%rsp), $r_ptr	# 2*U1*H^2
    #call	__secp256k1_mul_by_2	# secp256k1_mul_by_2(Hsqr, U2);

    xor	$t4, $t4
    add	$acc0, $acc0		# a0:a3+a0:a3
    lea	$Rsqr(%rsp), $a_ptr
    adc	$acc1, $acc1
     mov	$acc0, $t0
    adc	$acc2, $acc2
    adc	$acc3, $acc3
     mov	$acc1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $acc0
     mov	$acc2, $t2
    sbb	.Lpoly+8*1(%rip), $acc1
    sbb	.Lpoly+8*2(%rip), $acc2
     mov	$acc3, $t3
    sbb	.Lpoly+8*3(%rip), $acc3
    sbb	\$0, $t4

    cmovc	$t0, $acc0
    mov	8*0($a_ptr), $t0
    cmovc	$t1, $acc1
    mov	8*1($a_ptr), $t1
    cmovc	$t2, $acc2
    mov	8*2($a_ptr), $t2
    cmovc	$t3, $acc3
    mov	8*3($a_ptr), $t3

    call	__secp256k1_sub$x		# p256_sub(res_x, Rsqr, Hsqr);

    lea	$Hcub(%rsp), $b_ptr
    lea	$res_x(%rsp), $r_ptr
    call	__secp256k1_sub_from$x	# p256_sub(res_x, res_x, Hcub);

    mov	$U2+8*0(%rsp), $t0
    mov	$U2+8*1(%rsp), $t1
    mov	$U2+8*2(%rsp), $t2
    mov	$U2+8*3(%rsp), $t3
    lea	$res_y(%rsp), $r_ptr

    call	__secp256k1_sub$x		# p256_sub(res_y, U2, res_x);

    mov	$acc0, 8*0($r_ptr)		# save the result, as
    mov	$acc1, 8*1($r_ptr)		# __secp256k1_sub doesn't
    mov	$acc2, 8*2($r_ptr)
    mov	$acc3, 8*3($r_ptr)
___
}
$code.=<<___;
    `&load_for_mul("$S1(%rsp)", "$Hcub(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, S1, Hcub);

    `&load_for_mul("$R(%rsp)", "$res_y(%rsp)", "$src0")`
    lea	$res_y(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(res_y, R, res_y);

    lea	$S2(%rsp), $b_ptr
    lea	$res_y(%rsp), $r_ptr
    call	__secp256k1_sub_from$x	# p256_sub(res_y, res_y, S2);

    movq	%xmm0, $r_ptr		# restore $r_ptr

    movq    %xmm5, %r15
    movq    %xmm4, %r14

    movdqu $res_z(%rsp), %xmm0
    movdqu $res_z+0x10(%rsp), %xmm1
    movdqu $res_x(%rsp), %xmm2
    movdqu $res_x+0x10(%rsp), %xmm3
    movdqu $res_y(%rsp), %xmm4
    movdqu $res_y+0x10(%rsp), %xmm5

    cmp \$0, %r15
    je .add_in2inf$x
# in1inf
    movdqu $in2_z(%rsp), %xmm0
    movdqu $in2_z+0x10(%rsp), %xmm1
    movdqu $in2_x(%rsp), %xmm2
    movdqu $in2_x+0x10(%rsp), %xmm3
    movdqu $in2_y(%rsp), %xmm4
    movdqu $in2_y+0x10(%rsp), %xmm5

.add_in2inf$x:
    cmp \$0, %r14
    je .add_set_res$x
    movdqu $in1_z(%rsp), %xmm0
    movdqu $in1_z+0x10(%rsp), %xmm1
    movdqu $in1_x(%rsp), %xmm2
    movdqu $in1_x+0x10(%rsp), %xmm3
    movdqu $in1_y(%rsp), %xmm4
    movdqu $in1_y+0x10(%rsp), %xmm5

.add_set_res$x:
    movdqu %xmm0, 0x40($r_ptr)
    movdqu %xmm1, 0x50($r_ptr)
    movdqu %xmm2, 0x00($r_ptr)
    movdqu %xmm3, 0x10($r_ptr)
    movdqu %xmm4, 0x20($r_ptr)
    movdqu %xmm5, 0x30($r_ptr)

.Ladd_done$x:
    add	\$32*18+8, %rsp
    pop	%r15
    pop	%r14
    pop	%r13
    pop	%r12
    pop	%rbx
    pop	%rbp
    ret
.size	secp256k1_point_add$sfx,.-secp256k1_point_add$sfx
___
}
&gen_add("q");

sub gen_add_affine () {
    my $x = shift;
    my ($src0,$sfx,$bias);
    my ($U2,$S2,$H,$R,$Hsqr,$Hcub,$Rsqr,
    $res_x,$res_y,$res_z,
    $in1_x,$in1_y,$in1_z,
    $in2_x,$in2_y)=map(32*$_,(0..14));
    my $Z1sqr = $S2;

    if ($x ne "x") {
    $src0 = "%rax";
    $sfx  = "";
    $bias = 0;

$code.=<<___;
.globl	secp256k1_point_add_affine
.type	secp256k1_point_add_affine,\@function,3
.align	32
secp256k1_point_add_affine:
___
$code.=<<___	if ($addx);
    mov	\$0x80100, %ecx
    and	cpu_info+8(%rip), %ecx
    cmp	\$0x80100, %ecx
    je	.Lpoint_add_affinex
___
    } else {
    $src0 = "%rdx";
    $sfx  = "x";
    $bias = 128;

$code.=<<___;
.type	secp256k1_point_add_affinex,\@function,3
.align	32
secp256k1_point_add_affinex:
.Lpoint_add_affinex:
___
    }
$code.=<<___;
    push	%rbp
    push	%rbx
    push	%r12
    push	%r13
    push	%r14
    push	%r15
    sub	\$32*15+8, %rsp

    movdqu	0x00($a_ptr), %xmm0	# copy	*(POINT256 *)$a_ptr
    mov	$b_org, $b_ptr		# reassign
    movdqu	0x10($a_ptr), %xmm1
    movdqu	0x20($a_ptr), %xmm2
    movdqu	0x30($a_ptr), %xmm3
    movdqu	0x40($a_ptr), %xmm4
    movdqu	0x50($a_ptr), %xmm5
     mov	0x40+8*0($a_ptr), $src0	# load original in1_z
     mov	0x40+8*1($a_ptr), $acc6
     mov	0x40+8*2($a_ptr), $acc7
     mov	0x40+8*3($a_ptr), $acc0
    movdqa	%xmm0, $in1_x(%rsp)
    movdqa	%xmm1, $in1_x+0x10(%rsp)
    movdqa	%xmm2, $in1_y(%rsp)
    movdqa	%xmm3, $in1_y+0x10(%rsp)
    movdqa	%xmm4, $in1_z(%rsp)
    movdqa	%xmm5, $in1_z+0x10(%rsp)
    por	%xmm4, %xmm5

    movdqu	0x00($b_ptr), %xmm0	# copy	*(POINT256_AFFINE *)$b_ptr
     pshufd	\$0xb1, %xmm5, %xmm3
    movdqu	0x10($b_ptr), %xmm1
    movdqu	0x20($b_ptr), %xmm2
     por	%xmm3, %xmm5
    movdqu	0x30($b_ptr), %xmm3
    movdqa	%xmm0, $in2_x(%rsp)
     pshufd	\$0x1e, %xmm5, %xmm4
    movdqa	%xmm1, $in2_x+0x10(%rsp)
    por	%xmm0, %xmm1
     movq	$r_ptr, %xmm0		# save $r_ptr
    movdqa	%xmm2, $in2_y(%rsp)
    movdqa	%xmm3, $in2_y+0x10(%rsp)
    por	%xmm2, %xmm3
     por	%xmm4, %xmm5
     pxor	%xmm4, %xmm4
    por	%xmm1, %xmm3

    lea	0x40-$bias($a_ptr), $a_ptr	# $a_ptr is still valid
    lea	$Z1sqr(%rsp), $r_ptr		# Z1^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Z1sqr, in1_z);

    pcmpeqd	%xmm4, %xmm5
    pshufd	\$0xb1, %xmm3, %xmm4
     mov	0x00($b_ptr), $src0		# $b_ptr is still valid
     #lea	0x00($b_ptr), $b_ptr
     mov	$acc4, $acc1			# harmonize sqr output and mul input
    por	%xmm3, %xmm4
    pshufd	\$0, %xmm5, %xmm5		# in1infty
    pshufd	\$0x1e, %xmm4, %xmm3
     mov	$acc5, $acc2
    por	%xmm3, %xmm4
    pxor	%xmm3, %xmm3
     mov	$acc6, $acc3
    pcmpeqd	%xmm3, %xmm4
    pshufd	\$0, %xmm4, %xmm4		# in2infty

    lea	$Z1sqr-$bias(%rsp), $a_ptr
    mov	$acc7, $acc4
    lea	$U2(%rsp), $r_ptr		# U2 = X2*Z1^2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(U2, Z1sqr, in2_x);

    lea	$in1_x(%rsp), $b_ptr
    lea	$H(%rsp), $r_ptr		# H = U2 - U1
    call	__secp256k1_sub_from$x	# p256_sub(H, U2, in1_x);

    `&load_for_mul("$Z1sqr(%rsp)", "$in1_z(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr		# S2 = Z1^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, Z1sqr, in1_z);

    `&load_for_mul("$H(%rsp)", "$in1_z(%rsp)", "$src0")`
    lea	$res_z(%rsp), $r_ptr		# Z3 = H*Z1*Z2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(res_z, H, in1_z);

    `&load_for_mul("$S2(%rsp)", "$in2_y(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr		# S2 = Y2*Z1^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, S2, in2_y);

    lea	$in1_y(%rsp), $b_ptr
    lea	$R(%rsp), $r_ptr		# R = S2 - S1
    call	__secp256k1_sub_from$x	# p256_sub(R, S2, in1_y);

    `&load_for_sqr("$H(%rsp)", "$src0")`
    lea	$Hsqr(%rsp), $r_ptr		# H^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Hsqr, H);

    `&load_for_sqr("$R(%rsp)", "$src0")`
    lea	$Rsqr(%rsp), $r_ptr		# R^2
    call	__secp256k1_sqr_mont$x	# p256_sqr_mont(Rsqr, R);

    `&load_for_mul("$H(%rsp)", "$Hsqr(%rsp)", "$src0")`
    lea	$Hcub(%rsp), $r_ptr		# H^3
    call	__secp256k1_mul_mont$x	# p256_mul_mont(Hcub, Hsqr, H);

    `&load_for_mul("$Hsqr(%rsp)", "$in1_x(%rsp)", "$src0")`
    lea	$U2(%rsp), $r_ptr		# U1*H^2
    call	__secp256k1_mul_mont$x	# p256_mul_mont(U2, in1_x, Hsqr);
___
{
#######################################################################
# operate in 4-5-0-1 "name space" that matches multiplication output
#
my ($acc0,$acc1,$acc2,$acc3,$t3,$t4)=($acc4,$acc5,$acc0,$acc1,$acc2,$acc3);
my ($poly1, $poly3)=($acc6,$acc7);

$code.=<<___;
    #lea	$U2(%rsp), $a_ptr
    #lea	$Hsqr(%rsp), $r_ptr	# 2*U1*H^2
    #call	__secp256k1_mul_by_2	# secp256k1_mul_by_2(Hsqr, U2);

    xor	$t4, $t4
    add	$acc0, $acc0		# a0:a3+a0:a3
    lea	$Rsqr(%rsp), $a_ptr
    adc	$acc1, $acc1
     mov	$acc0, $t0
    adc	$acc2, $acc2
    adc	$acc3, $acc3
     mov	$acc1, $t1
    adc	\$0, $t4

    sub	.Lpoly+8*0(%rip), $acc0
     mov	$acc2, $t2
    sbb	.Lpoly+8*1(%rip), $acc1
    sbb	.Lpoly+8*2(%rip), $acc2
     mov	$acc3, $t3
    sbb	.Lpoly+8*3(%rip), $acc3
    sbb	\$0, $t4

    cmovc	$t0, $acc0
    mov	8*0($a_ptr), $t0
    cmovc	$t1, $acc1
    mov	8*1($a_ptr), $t1
    cmovc	$t2, $acc2
    mov	8*2($a_ptr), $t2
    cmovc	$t3, $acc3
    mov	8*3($a_ptr), $t3

    call	__secp256k1_sub$x		# p256_sub(res_x, Rsqr, Hsqr);

    lea	$Hcub(%rsp), $b_ptr
    lea	$res_x(%rsp), $r_ptr
    call	__secp256k1_sub_from$x	# p256_sub(res_x, res_x, Hcub);

    mov	$U2+8*0(%rsp), $t0
    mov	$U2+8*1(%rsp), $t1
    mov	$U2+8*2(%rsp), $t2
    mov	$U2+8*3(%rsp), $t3
    lea	$H(%rsp), $r_ptr

    call	__secp256k1_sub$x		# p256_sub(H, U2, res_x);

    mov	$acc0, 8*0($r_ptr)		# save the result, as
    mov	$acc1, 8*1($r_ptr)		# __secp256k1_sub doesn't
    mov	$acc2, 8*2($r_ptr)
    mov	$acc3, 8*3($r_ptr)
___
}
$code.=<<___;
    `&load_for_mul("$Hcub(%rsp)", "$in1_y(%rsp)", "$src0")`
    lea	$S2(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(S2, Hcub, in1_y);

    `&load_for_mul("$H(%rsp)", "$R(%rsp)", "$src0")`
    lea	$H(%rsp), $r_ptr
    call	__secp256k1_mul_mont$x	# p256_mul_mont(H, H, R);

    lea	$S2(%rsp), $b_ptr
    lea	$res_y(%rsp), $r_ptr
    call	__secp256k1_sub_from$x	# p256_sub(res_y, H, S2);

    movq	%xmm0, $r_ptr		# restore $r_ptr
    movq    %xmm5, %r15
    movq    %xmm4, %r14

    movdqu $res_z(%rsp), %xmm0
    movdqu $res_z+0x10(%rsp), %xmm1
    movdqu $res_x(%rsp), %xmm2
    movdqu $res_x+0x10(%rsp), %xmm3
    movdqu $res_y(%rsp), %xmm4
    movdqu $res_y+0x10(%rsp), %xmm5

    cmp \$0, %r15
    je .adda_in2inf$x
# in1inf
    movdqu .LONE_mont(%rip), %xmm0
    movdqu .LONE_mont+0x10(%rip), %xmm1
    movdqu $in2_x(%rsp), %xmm2
    movdqu $in2_x+0x10(%rsp), %xmm3
    movdqu $in2_y(%rsp), %xmm4
    movdqu $in2_y+0x10(%rsp), %xmm5

.adda_in2inf$x:
    cmp \$0, %r14
    je .adda_set_res$x
    movdqu $in1_z(%rsp), %xmm0
    movdqu $in1_z+0x10(%rsp), %xmm1
    movdqu $in1_x(%rsp), %xmm2
    movdqu $in1_x+0x10(%rsp), %xmm3
    movdqu $in1_y(%rsp), %xmm4
    movdqu $in1_y+0x10(%rsp), %xmm5

.adda_set_res$x:
    movdqu %xmm0, 0x40($r_ptr)
    movdqu %xmm1, 0x50($r_ptr)
    movdqu %xmm2, 0x00($r_ptr)
    movdqu %xmm3, 0x10($r_ptr)
    movdqu %xmm4, 0x20($r_ptr)
    movdqu %xmm5, 0x30($r_ptr)

    add	\$32*15+8, %rsp
    pop	%r15
    pop	%r14
    pop	%r13
    pop	%r12
    pop	%rbx
    pop	%rbp
    ret
.size	secp256k1_point_add_affine$sfx,.-secp256k1_point_add_affine$sfx
___
}
&gen_add_affine("q");

########################################################################
# AD*X magic
#
if ($addx) {								{
########################################################################
# operate in 4-5-0-1 "name space" that matches multiplication output
#
my ($a0,$a1,$a2,$a3,$t3,$t4)=($acc4,$acc5,$acc0,$acc1,$acc2,$acc3);

$code.=<<___;
.type	__secp256k1_add_tox,\@abi-omnipotent
.align	32
__secp256k1_add_tox:
    xor	$t4, $t4
    adc	8*0($b_ptr), $a0
    adc	8*1($b_ptr), $a1
     mov	$a0, $t0
    adc	8*2($b_ptr), $a2
    adc	8*3($b_ptr), $a3
     mov	$a1, $t1
    adc	\$0, $t4

    xor	$t3, $t3
    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_add_tox,.-__secp256k1_add_tox

.type	__secp256k1_sub_fromx,\@abi-omnipotent
.align	32
__secp256k1_sub_fromx:
    xor	$t4, $t4
    sbb	8*0($b_ptr), $a0
    sbb	8*1($b_ptr), $a1
     mov	$a0, $t0
    sbb	8*2($b_ptr), $a2
    sbb	8*3($b_ptr), $a3
     mov	$a1, $t1
    sbb	\$0, $t4

    xor	$t3, $t3
    add	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    adc	.Lpoly+8*1(%rip), $a1
    adc	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    adc	.Lpoly+8*3(%rip), $a3

    bt	\$0, $t4
    cmovnc	$t0, $a0
    cmovnc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovnc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovnc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_sub_fromx,.-__secp256k1_sub_fromx

.type	__secp256k1_subx,\@abi-omnipotent
.align	32
__secp256k1_subx:
    xor	$t4, $t4
    sbb	$a0, $t0
    sbb	$a1, $t1
     mov	$t0, $a0
    sbb	$a2, $t2
    sbb	$a3, $t3
     mov	$t1, $a1
    sbb	\$0, $t4

    xor	$a3 ,$a3
    add	.Lpoly+8*0(%rip), $t0
     mov	$t2, $a2
    adc	.Lpoly+8*1(%rip), $t1
    adc	.Lpoly+8*2(%rip), $t2
     mov	$t3, $a3
    adc	.Lpoly+8*3(%rip), $t3

    bt	\$0, $t4
    cmovc	$t0, $a0
    cmovc	$t1, $a1
    cmovc	$t2, $a2
    cmovc	$t3, $a3

    ret
.size	__secp256k1_subx,.-__secp256k1_subx

.type	__secp256k1_mul_by_2x,\@abi-omnipotent
.align	32
__secp256k1_mul_by_2x:
    xor	$t4, $t4
    adc	$a0, $a0		# a0:a3+a0:a3
    adc	$a1, $a1
     mov	$a0, $t0
    adc	$a2, $a2
    adc	$a3, $a3
     mov	$a1, $t1
    adc	\$0, $t4

    xor	$t3, $t3
    sub	.Lpoly+8*0(%rip), $a0
     mov	$a2, $t2
    sbb	.Lpoly+8*1(%rip), $a1
    sbb	.Lpoly+8*2(%rip), $a2
     mov	$a3, $t3
    sbb	.Lpoly+8*3(%rip), $a3
    sbb	\$0, $t4

    cmovc	$t0, $a0
    cmovc	$t1, $a1
    mov	$a0, 8*0($r_ptr)
    cmovc	$t2, $a2
    mov	$a1, 8*1($r_ptr)
    cmovc	$t3, $a3
    mov	$a2, 8*2($r_ptr)
    mov	$a3, 8*3($r_ptr)

    ret
.size	__secp256k1_mul_by_2x,.-__secp256k1_mul_by_2x
___
                                    }
&gen_double("x");
&gen_add("x");
&gen_add_affine("x");
}
}}}

$code =~ s/\`([^\`]*)\`/eval $1/gem;
print $code;
close STDOUT or die "error closing STDOUT: $!";

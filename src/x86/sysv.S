/* -----------------------------------------------------------------------
   sysv.S - Copyright (c) 2013  The Written Word, Inc.
	  - Copyright (c) 1996,1998,2001-2003,2005,2008,2010  Red Hat, Inc.
   
   X86 Foreign Function Interface 

   Permission is hereby granted, free of charge, to any person obtaining
   a copy of this software and associated documentation files (the
   ``Software''), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to
   permit persons to whom the Software is furnished to do so, subject to
   the following conditions:

   The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED ``AS IS'', WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
   DEALINGS IN THE SOFTWARE.
   ----------------------------------------------------------------------- */

#ifndef __x86_64__

#define LIBFFI_ASM	
#include <fficonfig.h>
#include <ffi.h>
#include "internal.h"

#define C2(X, Y)  X ## Y
#define C1(X, Y)  C2(X, Y)
#ifdef __USER_LABEL_PREFIX__
# define C(X)     C1(__USER_LABEL_PREFIX__, X)
#else
# define C(X)     X
#endif

#ifdef X86_DARWIN
# define L(X)     C1(L, X)
#else
# define L(X)     C1(.L, X)
#endif

#ifdef __ELF__
# define ENDF(X)  .type	X,@function; .size X, . - X
#else
# define ENDF(X)
#endif

/* Handle win32 fastcall name mangling.  */
#ifdef X86_WIN32
# define ffi_call_i386		@ffi_call_i386@8
# define ffi_closure_inner	@ffi_closure_inner@8
#else
# define ffi_call_i386		C(ffi_call_i386)
# define ffi_closure_inner	C(ffi_closure_inner)
#endif

/* This macro allows the safe creation of jump tables without an
   actual table.  The entry points into the table are all 8 bytes.
   The use of ORG asserts that we're at the correct location.  */
/* ??? The clang assembler doesn't handle .org with symbolic expressions.  */
#if defined(__clang__) || defined(__APPLE__)
# define E(BASE, X)	.balign 8
#else
# define E(BASE, X)	.balign 8; .org BASE + X * 8
#endif

	.text
	.balign	16
	.globl	ffi_call_i386
	FFI_HIDDEN(ffi_call_i386)

/* This is declared as

   void ffi_call_i386(struct call_frame *frame, char *argp)
        __attribute__((fastcall));

   Thus the arguments are present in

        ecx: frame
        edx: argp
*/

ffi_call_i386:
L(UW0):
	.cfi_startproc
#if !HAVE_FASTCALL
	movl	4(%esp), %ecx
	movl	8(%esp), %edx
#endif
	movl	(%esp), %eax		/* move the return address */
	movl	%ebp, (%ecx)		/* store %ebp into local frame */
	movl	%eax, 4(%ecx)		/* store retaddr into local frame */

	/* New stack frame based off ebp.  This is a itty bit of unwind
	   trickery in that the CFA *has* changed.  There is no easy way
	   to describe it correctly on entry to the function.  Fortunately,
	   it doesn't matter too much since at all points we can correctly
	   unwind back to ffi_call.  Note that the location to which we
	   moved the return address is (the new) CFA-4, so from the
	   perspective of the unwind info, it hasn't moved.  */
	movl	%ecx, %ebp
L(UW1):
	.cfi_def_cfa %ebp, 8
	.cfi_rel_offset %ebp, 0

	movl	%edx, %esp		/* set outgoing argument stack */
	movl	20+R_EAX*4(%ebp), %eax	/* set register arguments */
	movl	20+R_EDX*4(%ebp), %edx
	movl	20+R_ECX*4(%ebp), %ecx

	call	*8(%ebp)

	movl	12(%ebp), %ecx		/* load return type code */
	movl	%ebx, 8(%ebp)		/* preserve %ebx */
L(UW2):
	.cfi_rel_offset %ebx, 8

	andl	$X86_RET_TYPE_MASK, %ecx
#ifdef __PIC__
	call	C(__x86.get_pc_thunk.bx)
L(pc1):
	leal	L(store_table)-L(pc1)(%ebx, %ecx, 8), %ebx
#else
	leal	L(store_table)(,%ecx, 8), %ebx
#endif
	movl	16(%ebp), %ecx		/* load result address */
	jmp	*%ebx

	.balign	8
L(store_table):
E(L(store_table), X86_RET_FLOAT)
	fstps	(%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_DOUBLE)
	fstpl	(%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_LDOUBLE)
	fstpt	(%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_SINT8)
	movsbl	%al, %eax
	mov	%eax, (%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_SINT16)
	movswl	%ax, %eax
	mov	%eax, (%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_UINT8)
	movzbl	%al, %eax
	mov	%eax, (%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_UINT16)
	movzwl	%ax, %eax
	mov	%eax, (%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_INT64)
	movl	%edx, 4(%ecx)
	/* fallthru */
E(L(store_table), X86_RET_INT32)
	movl	%eax, (%ecx)
	/* fallthru */
E(L(store_table), X86_RET_VOID)
L(e1):
	movl	8(%ebp), %ebx
	movl	%ebp, %esp
	popl	%ebp
L(UW3):
	.cfi_remember_state
	.cfi_def_cfa %esp, 4
	.cfi_restore %ebx
	.cfi_restore %ebp
	ret
L(UW4):
	.cfi_restore_state

E(L(store_table), X86_RET_STRUCTPOP)
	jmp	L(e1)
E(L(store_table), X86_RET_STRUCTARG)
	jmp	L(e1)
E(L(store_table), X86_RET_STRUCT_1B)
	movb	%al, (%ecx)
	jmp	L(e1)
E(L(store_table), X86_RET_STRUCT_2B)
	movw	%ax, (%ecx)
	jmp	L(e1)

	/* Fill out the table so that bad values are predictable.  */
E(L(store_table), X86_RET_UNUSED14)
	ud2
E(L(store_table), X86_RET_UNUSED15)
	ud2

L(UW5):
	.cfi_endproc
ENDF(ffi_call_i386)

/* The inner helper is declared as

   void ffi_closure_inner(struct closure_frame *frame, char *argp)
	__attribute_((fastcall))

   Thus the arguments are placed in

	ecx:	frame
	edx:	argp
*/

/* Macros to help setting up the closure_data structure.  */

#if HAVE_FASTCALL
# define closure_FS	(40 + 4)
# define closure_CF	0
#else
# define closure_FS	(8 + 40 + 12)
# define closure_CF	8
#endif

#define FFI_CLOSURE_SAVE_REGS		\
	movl	%eax, closure_CF+16+R_EAX*4(%esp);	\
	movl	%edx, closure_CF+16+R_EDX*4(%esp);	\
	movl	%ecx, closure_CF+16+R_ECX*4(%esp)

#define FFI_CLOSURE_COPY_TRAMP_DATA					\
	movl	FFI_TRAMPOLINE_SIZE(%eax), %edx;	/* copy cif */	\
	movl	FFI_TRAMPOLINE_SIZE+4(%eax), %ecx;	/* copy fun */	\
	movl	FFI_TRAMPOLINE_SIZE+8(%eax), %eax;	/* copy user_data */ \
	movl	%edx, closure_CF+28(%esp);				\
	movl	%ecx, closure_CF+32(%esp);				\
	movl	%eax, closure_CF+36(%esp)

#if HAVE_FASTCALL
# define FFI_CLOSURE_PREP_CALL						\
	movl	%esp, %ecx;			/* load closure_data */	\
	leal	closure_FS+4(%esp), %edx;	/* load incoming stack */
#else
# define FFI_CLOSURE_PREP_CALL						\
	leal	closure_CF(%esp), %ecx;		/* load closure_data */	\
	leal	closure_FS+4(%esp), %edx;	/* load incoming stack */ \
	movl	%ecx, (%esp);						\
	movl	%edx, 4(%esp)
#endif

#define FFI_CLOSURE_CALL_INNER(UWN) \
	call	ffi_closure_inner

#define FFI_CLOSURE_MASK_AND_JUMP(N, UW)				\
	andl	$X86_RET_TYPE_MASK, %eax;				\
	leal	L(C1(load_table,N))(, %eax, 8), %edx;			\
	movl	closure_CF(%esp), %eax;		/* optimiztic load */	\
	jmp	*%edx

#ifdef __PIC__
# if defined X86_DARWIN || defined HAVE_HIDDEN_VISIBILITY_ATTRIBUTE
#  undef FFI_CLOSURE_MASK_AND_JUMP
#  define FFI_CLOSURE_MASK_AND_JUMP(N, UW)				\
	andl	$X86_RET_TYPE_MASK, %eax;				\
	call	C(__x86.get_pc_thunk.dx);				\
L(C1(pc,N)):								\
	leal	L(C1(load_table,N))-L(C1(pc,N))(%edx, %eax, 8), %edx;	\
	movl	closure_CF(%esp), %eax;		/* optimiztic load */	\
	jmp	*%edx
# else
#  define FFI_CLOSURE_CALL_INNER_SAVE_EBX
#  undef FFI_CLOSURE_CALL_INNER
#  define FFI_CLOSURE_CALL_INNER(UWN)					\
	movl	%ebx, 40(%esp);			/* save ebx */		\
L(C1(UW,UWN)):								\
	.cfi_rel_offset %ebx, 40;					\
	call	C(__x86.get_pc_thunk.bx);	/* load got register */	\
	addl	$C(_GLOBAL_OFFSET_TABLE_), %ebx;			\
	call	ffi_closure_inner@PLT
#  undef FFI_CLOSURE_MASK_AND_JUMP
#  define FFI_CLOSURE_MASK_AND_JUMP(N, UWN)				\
	andl	$X86_RET_TYPE_MASK, %eax;				\
	leal	L(C1(load_table,N))@GOTOFF(%ebx, %eax, 8), %edx;	\
	movl	40(%esp), %ebx;			/* restore ebx */	\
L(C1(UW,UWN)):								\
	.cfi_restore %ebx;						\
	movl	closure_CF(%esp), %eax;		/* optimiztic load */	\
	jmp	*%edx
# endif /* DARWIN || HIDDEN */
#endif /* __PIC__ */

	.balign	16
	.globl	C(ffi_go_closure_EAX)
	FFI_HIDDEN(C(ffi_go_closure_EAX))
C(ffi_go_closure_EAX):
L(UW6):
	.cfi_startproc
	subl	$closure_FS, %esp
L(UW7):
	.cfi_def_cfa_offset closure_FS + 4
	FFI_CLOSURE_SAVE_REGS
	movl	4(%eax), %edx			/* copy cif */
	movl	8(%eax), %ecx			/* copy fun */
	movl	%edx, closure_CF+28(%esp)
	movl	%ecx, closure_CF+32(%esp)
	movl	%eax, closure_CF+36(%esp)	/* closure is user_data */
	jmp	L(do_closure_i386)
L(UW8):
	.cfi_endproc
ENDF(C(ffi_go_closure_EAX))

	.balign	16
	.globl	C(ffi_go_closure_ECX)
	FFI_HIDDEN(C(ffi_go_closure_ECX))
C(ffi_go_closure_ECX):
L(UW9):
	.cfi_startproc
	subl	$closure_FS, %esp
L(UW10):
	.cfi_def_cfa_offset closure_FS + 4
	FFI_CLOSURE_SAVE_REGS
	movl	4(%ecx), %edx			/* copy cif */
	movl	8(%ecx), %eax			/* copy fun */
	movl	%edx, closure_CF+28(%esp)
	movl	%eax, closure_CF+32(%esp)
	movl	%ecx, closure_CF+36(%esp)	/* closure is user_data */
	jmp	L(do_closure_i386)
L(UW11):
	.cfi_endproc
ENDF(C(ffi_go_closure_ECX))

/* The closure entry points are reached from the ffi_closure trampoline.
   On entry, %eax contains the address of the ffi_closure.  */

	.balign	16
	.globl	C(ffi_closure_i386)
	FFI_HIDDEN(C(ffi_closure_i386))

C(ffi_closure_i386):
L(UW12):
	.cfi_startproc
	subl	$closure_FS, %esp
L(UW13):
	.cfi_def_cfa_offset closure_FS + 4

	FFI_CLOSURE_SAVE_REGS
	FFI_CLOSURE_COPY_TRAMP_DATA

	/* Entry point from preceeding Go closures.  */
L(do_closure_i386):

	FFI_CLOSURE_PREP_CALL
	FFI_CLOSURE_CALL_INNER(14)
	FFI_CLOSURE_MASK_AND_JUMP(2, 15)

	.balign	8
L(load_table2):
E(L(load_table2), X86_RET_FLOAT)
	flds	closure_CF(%esp)
	jmp	L(e2)
E(L(load_table2), X86_RET_DOUBLE)
	fldl	closure_CF(%esp)
	jmp	L(e2)
E(L(load_table2), X86_RET_LDOUBLE)
	fldt	closure_CF(%esp)
	jmp	L(e2)
E(L(load_table2), X86_RET_SINT8)
	movsbl	%al, %eax
	jmp	L(e2)
E(L(load_table2), X86_RET_SINT16)
	movswl	%ax, %eax
	jmp	L(e2)
E(L(load_table2), X86_RET_UINT8)
	movzbl	%al, %eax
	jmp	L(e2)
E(L(load_table2), X86_RET_UINT16)
	movzwl	%ax, %eax
	jmp	L(e2)
E(L(load_table2), X86_RET_INT64)
	movl	closure_CF+4(%esp), %edx
	jmp	L(e2)
E(L(load_table2), X86_RET_INT32)
	nop
	/* fallthru */
E(L(load_table2), X86_RET_VOID)
L(e2):
	addl	$closure_FS, %esp
L(UW16):
	.cfi_adjust_cfa_offset -closure_FS
	ret
L(UW17):
	.cfi_adjust_cfa_offset closure_FS
E(L(load_table2), X86_RET_STRUCTPOP)
	addl	$closure_FS, %esp
L(UW18):
	.cfi_adjust_cfa_offset -closure_FS
	ret	$4
L(UW19):
	.cfi_adjust_cfa_offset closure_FS
E(L(load_table2), X86_RET_STRUCTARG)
	jmp	L(e2)
E(L(load_table2), X86_RET_STRUCT_1B)
	movzbl	%al, %eax
	jmp	L(e2)
E(L(load_table2), X86_RET_STRUCT_2B)
	movzwl	%ax, %eax
	jmp	L(e2)

	/* Fill out the table so that bad values are predictable.  */
E(L(load_table2), X86_RET_UNUSED14)
	ud2
E(L(load_table2), X86_RET_UNUSED15)
	ud2

L(UW20):
	.cfi_endproc
ENDF(C(ffi_closure_i386))

	.balign	16
	.globl	C(ffi_go_closure_STDCALL)
	FFI_HIDDEN(C(ffi_go_closure_STDCALL))
C(ffi_go_closure_STDCALL):
L(UW21):
	.cfi_startproc
	subl	$closure_FS, %esp
L(UW22):
	.cfi_def_cfa_offset closure_FS + 4
	FFI_CLOSURE_SAVE_REGS
	movl	4(%ecx), %edx			/* copy cif */
	movl	8(%ecx), %eax			/* copy fun */
	movl	%edx, closure_CF+28(%esp)
	movl	%eax, closure_CF+32(%esp)
	movl	%ecx, closure_CF+36(%esp)	/* closure is user_data */
	jmp	L(do_closure_STDCALL)
L(UW23):
	.cfi_endproc
ENDF(C(ffi_go_closure_STDCALL))

/* For REGISTER, we have no available parameter registers, and so we
   enter here having pushed the closure onto the stack.  */

	.balign	16
	.globl	C(ffi_closure_REGISTER)
	FFI_HIDDEN(C(ffi_closure_REGISTER))
C(ffi_closure_REGISTER):
L(UW24):
	.cfi_startproc
	.cfi_def_cfa %esp, 8
	.cfi_offset %eip, -8
	subl	$closure_FS-4, %esp
L(UW25):
	.cfi_def_cfa_offset closure_FS + 4
	FFI_CLOSURE_SAVE_REGS
	movl	closure_FS-4(%esp), %ecx	/* load retaddr */
	movl	closure_FS(%esp), %eax		/* load closure */
	movl	%ecx, closure_FS(%esp)		/* move retaddr */
	jmp	L(do_closure_REGISTER)
L(UW26):
	.cfi_endproc
ENDF(C(ffi_closure_REGISTER))

/* For STDCALL (and others), we need to pop N bytes of arguments off
   the stack following the closure.  The amount needing to be popped
   is returned to us from ffi_closure_inner.  */

	.balign	16
	.globl	C(ffi_closure_STDCALL)
	FFI_HIDDEN(C(ffi_closure_STDCALL))
C(ffi_closure_STDCALL):
L(UW27):
	.cfi_startproc
	subl	$closure_FS, %esp
L(UW28):
	.cfi_def_cfa_offset closure_FS + 4

	FFI_CLOSURE_SAVE_REGS

	/* Entry point from ffi_closure_REGISTER.  */
L(do_closure_REGISTER):

	FFI_CLOSURE_COPY_TRAMP_DATA

	/* Entry point from preceeding Go closure.  */
L(do_closure_STDCALL):

	FFI_CLOSURE_PREP_CALL
	FFI_CLOSURE_CALL_INNER(29)

	movl	%eax, %ecx
	shrl	$X86_RET_POP_SHIFT, %ecx	/* isolate pop count */
	leal	closure_FS(%esp, %ecx), %ecx	/* compute popped esp */
	movl	closure_FS(%esp), %edx		/* move return address */
	movl	%edx, (%ecx)

	/* From this point on, the value of %esp upon return is %ecx+4,
	   and we've copied the return address to %ecx to make return easy.
	   There's no point in representing this in the unwind info, as
	   there is always a window between the mov and the ret which
	   will be wrong from one point of view or another.  */

	FFI_CLOSURE_MASK_AND_JUMP(3, 30)

	.balign	8
L(load_table3):
E(L(load_table3), X86_RET_FLOAT)
	flds    closure_CF(%esp)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_DOUBLE)
	fldl    closure_CF(%esp)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_LDOUBLE)
	fldt    closure_CF(%esp)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_SINT8)
	movsbl  %al, %eax
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_SINT16)
	movswl  %ax, %eax
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_UINT8)
	movzbl  %al, %eax
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_UINT16)
	movzwl  %ax, %eax
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_INT64)
	movl	closure_CF+4(%esp), %edx
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_INT32)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_VOID)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_STRUCTPOP)
	movl    %ecx, %esp
	ret
E(L(load_table3), X86_RET_STRUCTARG)
	movl	%ecx, %esp
	ret
E(L(load_table3), X86_RET_STRUCT_1B)
	movzbl	%al, %eax
	movl	%ecx, %esp
	ret
E(L(load_table3), X86_RET_STRUCT_2B)
	movzwl	%ax, %eax
	movl	%ecx, %esp
	ret

	/* Fill out the table so that bad values are predictable.  */
E(L(load_table3), X86_RET_UNUSED14)
	ud2
E(L(load_table3), X86_RET_UNUSED15)
	ud2

L(UW31):
	.cfi_endproc
ENDF(C(ffi_closure_STDCALL))

#if !FFI_NO_RAW_API

#define raw_closure_S_FS	(16+16+12)

	.balign	16
	.globl	C(ffi_closure_raw_SYSV)
	FFI_HIDDEN(C(ffi_closure_raw_SYSV))
C(ffi_closure_raw_SYSV):
L(UW32):
	.cfi_startproc
	subl	$raw_closure_S_FS, %esp
L(UW33):
	.cfi_def_cfa_offset raw_closure_S_FS + 4
	movl	%ebx, raw_closure_S_FS-4(%esp)
L(UW34):
	.cfi_rel_offset %ebx, raw_closure_S_FS-4

	movl	FFI_TRAMPOLINE_SIZE+8(%eax), %edx	/* load cl->user_data */
	movl	%edx, 12(%esp)
	leal	raw_closure_S_FS+4(%esp), %edx		/* load raw_args */
	movl	%edx, 8(%esp)
	leal	16(%esp), %edx				/* load &res */
	movl	%edx, 4(%esp)
	movl	FFI_TRAMPOLINE_SIZE(%eax), %ebx		/* load cl->cif */
	movl	%ebx, (%esp)
	call	*FFI_TRAMPOLINE_SIZE+4(%eax)		/* call cl->fun */

	movl	20(%ebx), %eax				/* load cif->flags */
	andl	$X86_RET_TYPE_MASK, %eax
#ifdef __PIC__
	call	C(__x86.get_pc_thunk.bx)
L(pc4):
	leal	L(load_table4)-L(pc4)(%ebx, %eax, 8), %ecx
#else
	leal	L(load_table4)(,%eax, 8), %ecx
#endif
	movl	raw_closure_S_FS-4(%esp), %ebx
L(UW35):
	.cfi_restore %ebx
	movl	16(%esp), %eax				/* Optimistic load */
	jmp	*%ecx

	.balign	8
L(load_table4):
E(L(load_table4), X86_RET_FLOAT)
	flds	16(%esp)
	jmp	L(e4)
E(L(load_table4), X86_RET_DOUBLE)
	fldl	16(%esp)
	jmp	L(e4)
E(L(load_table4), X86_RET_LDOUBLE)
	fldt	16(%esp)
	jmp	L(e4)
E(L(load_table4), X86_RET_SINT8)
	movsbl	%al, %eax
	jmp	L(e4)
E(L(load_table4), X86_RET_SINT16)
	movswl	%ax, %eax
	jmp	L(e4)
E(L(load_table4), X86_RET_UINT8)
	movzbl	%al, %eax
	jmp	L(e4)
E(L(load_table4), X86_RET_UINT16)
	movzwl	%ax, %eax
	jmp	L(e4)
E(L(load_table4), X86_RET_INT64)
	movl	16+4(%esp), %edx
	jmp	L(e4)
E(L(load_table4), X86_RET_INT32)
	nop
	/* fallthru */
E(L(load_table4), X86_RET_VOID)
L(e4):
	addl	$raw_closure_S_FS, %esp
L(UW36):
	.cfi_adjust_cfa_offset -raw_closure_S_FS
	ret
L(UW37):
	.cfi_adjust_cfa_offset raw_closure_S_FS
E(L(load_table4), X86_RET_STRUCTPOP)
	addl	$raw_closure_S_FS, %esp
L(UW38):
	.cfi_adjust_cfa_offset -raw_closure_S_FS
	ret	$4
L(UW39):
	.cfi_adjust_cfa_offset raw_closure_S_FS
E(L(load_table4), X86_RET_STRUCTARG)
	jmp	L(e4)
E(L(load_table4), X86_RET_STRUCT_1B)
	movzbl	%al, %eax
	jmp	L(e4)
E(L(load_table4), X86_RET_STRUCT_2B)
	movzwl	%ax, %eax
	jmp	L(e4)

	/* Fill out the table so that bad values are predictable.  */
E(L(load_table4), X86_RET_UNUSED14)
	ud2
E(L(load_table4), X86_RET_UNUSED15)
	ud2

L(UW40):
	.cfi_endproc
ENDF(C(ffi_closure_raw_SYSV))

#define raw_closure_T_FS	(16+16+8)

	.balign	16
	.globl	C(ffi_closure_raw_THISCALL)
	FFI_HIDDEN(C(ffi_closure_raw_THISCALL))
C(ffi_closure_raw_THISCALL):
L(UW41):
	.cfi_startproc
	/* Rearrange the stack such that %ecx is the first argument.
	   This means moving the return address.  */
	popl	%edx
L(UW42):
	.cfi_def_cfa_offset 0
	.cfi_register %eip, %edx
	pushl	%ecx
L(UW43):
	.cfi_adjust_cfa_offset 4
	pushl	%edx
L(UW44):
	.cfi_adjust_cfa_offset 4
	.cfi_rel_offset %eip, 0
	subl	$raw_closure_T_FS, %esp
L(UW45):
	.cfi_adjust_cfa_offset raw_closure_T_FS
	movl	%ebx, raw_closure_T_FS-4(%esp)
L(UW46):
	.cfi_rel_offset %ebx, raw_closure_T_FS-4

	movl	FFI_TRAMPOLINE_SIZE+8(%eax), %edx	/* load cl->user_data */
	movl	%edx, 12(%esp)
	leal	raw_closure_T_FS+4(%esp), %edx		/* load raw_args */
	movl	%edx, 8(%esp)
	leal	16(%esp), %edx				/* load &res */
	movl	%edx, 4(%esp)
	movl	FFI_TRAMPOLINE_SIZE(%eax), %ebx		/* load cl->cif */
	movl	%ebx, (%esp)
	call	*FFI_TRAMPOLINE_SIZE+4(%eax)		/* call cl->fun */

	movl	20(%ebx), %eax				/* load cif->flags */
	andl	$X86_RET_TYPE_MASK, %eax
#ifdef __PIC__
	call	C(__x86.get_pc_thunk.bx)
L(pc5):
	leal	L(load_table5)-L(pc5)(%ebx, %eax, 8), %ecx
#else
	leal	L(load_table5)(,%eax, 8), %ecx
#endif
	movl	raw_closure_T_FS-4(%esp), %ebx
L(UW47):
	.cfi_restore %ebx
	movl	16(%esp), %eax				/* Optimistic load */
	jmp	*%ecx

	.balign	8
L(load_table5):
E(L(load_table5), X86_RET_FLOAT)
	flds	16(%esp)
	jmp	L(e5)
E(L(load_table5), X86_RET_DOUBLE)
	fldl	16(%esp)
	jmp	L(e5)
E(L(load_table5), X86_RET_LDOUBLE)
	fldt	16(%esp)
	jmp	L(e5)
E(L(load_table5), X86_RET_SINT8)
	movsbl	%al, %eax
	jmp	L(e5)
E(L(load_table5), X86_RET_SINT16)
	movswl	%ax, %eax
	jmp	L(e5)
E(L(load_table5), X86_RET_UINT8)
	movzbl	%al, %eax
	jmp	L(e5)
E(L(load_table5), X86_RET_UINT16)
	movzwl	%ax, %eax
	jmp	L(e5)
E(L(load_table5), X86_RET_INT64)
	movl	16+4(%esp), %edx
	jmp	L(e5)
E(L(load_table5), X86_RET_INT32)
	nop
	/* fallthru */
E(L(load_table5), X86_RET_VOID)
L(e5):
	addl	$raw_closure_T_FS, %esp
L(UW48):
	.cfi_adjust_cfa_offset -raw_closure_T_FS
	/* Remove the extra %ecx argument we pushed.  */
	ret	$4
L(UW49):
	.cfi_adjust_cfa_offset raw_closure_T_FS
E(L(load_table5), X86_RET_STRUCTPOP)
	addl	$raw_closure_T_FS, %esp
L(UW50):
	.cfi_adjust_cfa_offset -raw_closure_T_FS
	ret	$8
L(UW51):
	.cfi_adjust_cfa_offset raw_closure_T_FS
E(L(load_table5), X86_RET_STRUCTARG)
	jmp	L(e5)
E(L(load_table5), X86_RET_STRUCT_1B)
	movzbl	%al, %eax
	jmp	L(e5)
E(L(load_table5), X86_RET_STRUCT_2B)
	movzwl	%ax, %eax
	jmp	L(e5)

	/* Fill out the table so that bad values are predictable.  */
E(L(load_table5), X86_RET_UNUSED14)
	ud2
E(L(load_table5), X86_RET_UNUSED15)
	ud2

L(UW52):
	.cfi_endproc
ENDF(C(ffi_closure_raw_THISCALL))

#endif /* !FFI_NO_RAW_API */

#ifdef X86_DARWIN
# define COMDAT(X)							\
        .section __TEXT,__textcoal_nt,coalesced,pure_instructions;	\
        .weak_definition X;						\
        .private_extern X
#elif defined __ELF__
# define COMDAT(X)							\
	.section .text.X,"axG",@progbits,X,comdat;			\
	.globl	X;							\
	FFI_HIDDEN(X)
#else
# define COMDAT(X)
#endif

#if defined(__PIC__)
	COMDAT(C(__x86.get_pc_thunk.bx))
C(__x86.get_pc_thunk.bx):
	movl	(%esp), %ebx
	ret
ENDF(C(__x86.get_pc_thunk.bx))
# if defined X86_DARWIN || defined HAVE_HIDDEN_VISIBILITY_ATTRIBUTE
	COMDAT(C(__x86.get_pc_thunk.dx))
C(__x86.get_pc_thunk.dx):
	movl	(%esp), %edx
	ret
ENDF(C(__x86.get_pc_thunk.dx))
#endif /* DARWIN || HIDDEN */
#endif /* __PIC__ */

#endif /* ifndef __x86_64__ */

#if defined __ELF__ && defined __linux__
	.section	.note.GNU-stack,"",@progbits
#endif

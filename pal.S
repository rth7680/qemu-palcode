	.set		noat
	.set		nomacro
	.text

#include "osf.h"

/* General Purpose Registers.  */
#define	v0	$0
#define t0	$1
#define t1	$2
#define t2	$3
#define t3	$4
#define t4	$5
#define t5	$6
#define a0	$16
#define a1	$17
#define a2	$18
#define a3	$19
#define a4	$20
#define a5	$21
#define t8	$22
#define t9	$23
#define t10	$24

/* PALcode Shadow Registers.  These registers are swapped out when
   QEMU is in PALmode.  Unlike real hardware, there is no enable bit.
   However, also unlike real hardware, the originals can be accessed
   via MTPR/MFPR.  */
#define p0	$8
#define p1	$9
#define p2	$10
#define p3	$11
#define p4	$12
#define p5	$13
#define p6	$14		// Used to save exc_addr for machine check
#define p7	$25

/* QEMU Processor Registers.  */
#define	qemu_ps		0
#define qemu_fen	1
#define qemu_pcc_ofs	2
#define qemu_trap_arg0	3
#define qemu_trap_arg1	4
#define qemu_trap_arg2	5
#define qemu_exc_addr	6
#define qemu_palbr	7
#define qemu_ptbr	8
#define qemu_vptptr	9
#define qemu_unique	10
#define qemu_lock_addr	11

#define qemu_shadow0	32
#define qemu_shadow1	33
#define qemu_shadow2	34
#define qemu_shadow3	35
#define qemu_shadow4	36
#define qemu_shadow5	37
#define qemu_shadow6	38
#define qemu_shadow7	39

/* PALcode Processor Register Private Storage.  */
#define pt0		40
#define pt1		41
#define pt2		42
#define pt3		43
#define pt4		44
#define pt5		45
#define pt6		46
#define pt7		47
#define pt8		48
#define pt9		49
#define pt10		50
#define pt11		51
#define pt12		52
#define pt13		53
#define pt14		54
#define pt15		55
#define pt16		56
#define pt17		57
#define pt18		58
#define pt19		59
#define pt20		60
#define pt21		61
#define pt22		62
#define pt23		63

/* QEMU function calls, via mtpr.  */
#define qemu_tbia	255
#define qemu_tbis	254

/* PALcode uses of the private storage slots.  */
#define ptEntUna	pt1
#define ptEntIF		pt2
#define ptEntSys	pt3
#define ptEntInt	pt4
#define ptEntArith	pt5
#define ptEntMM		pt6
#define ptMces		pt7
#define ptSysVal	pt8
#define ptUsp		pt9
#define ptKsp		pt10
#define ptKgp		pt11
#define ptPcbb		pt12
#define ptPgp		pt13
#define ptMchk0		pt14
#define ptMchk1		pt15
#define ptMisc		pt16
#define ptMchk2		pt17
#define ptMchk3		pt18
#define ptMchk4		pt19
#define ptMchk5		pt20

/*
 * Shortcuts for various PALmode instructions.
 */
#define mtpr	hw_mtpr
#define mfpr	hw_mfpr
#define stq_p	hw_stq/p
#define stl_p	hw_stl/p
#define ldl_p	hw_ldl/p
#define ldq_p	hw_ldq/p

/* QEMU recognizes the EV4/EV5 HW_REI instruction as a special case of
   the EV6 HW_RET instruction.  This pulls the destination address from
   the EXC_ADDR processor register.  */
#define hw_rei	hw_ret ($31)

/*
 * Create a standard kernel entry stack frame.
 */

#define FRM_Q_PS        0
#define FRM_Q_PC        8
#define FRM_Q_GP        16
#define FRM_Q_A0        24
#define FRM_Q_A1        32
#define FRM_Q_A2        40
#define FRM_K_SIZE      48

.macro	STACK_FRAME save_ps, save_pc, temp, do_ps
	// Test if we're currently in user mode
	and	\save_ps, PS_M_CM, \temp
	beq	\temp, 0f
	// Switch to kernel mode
.ifne \do_ps
	mtpr	$31, qemu_ps
.endif
	mtpr	$sp, ptUsp
	mfpr	$sp, ptKsp
	// Allocate the stack frame
0:	lda	$sp, -FRM_K_SIZE($sp)
	stq	\save_ps, FRM_Q_PS($sp)
	stq	\save_pc, FRM_Q_PC($sp)
	stq	$gp, FRM_Q_GP($sp)
	stq	a0, FRM_Q_A0($sp)
	stq	a1, FRM_Q_A1($sp)
	stq	a2, FRM_Q_A2($sp)
.endm

.macro	ENDFN	function
	.type	\function, @function
	.size	\function, . - \function
.endm

/*
 * Allocate a 1 page stack for use by the console.
 */
#define STACK_SIZE	8192

/*
 * QEMU emulator "hardware" entry points.
 */

/*
 * Reset
 * 
 * INPUT PARAMETERS:
 * 
 *	trap_arg0 = Memory size
 *	trap_arg1 = Kernel entry (if loaded)
 */ 
        .org	0x0000
	.globl	__start
__start:
	// Initialize GP and stack.
	br	$gp, .+4
	ldah	$gp, 0($gp)			!gpdisp!1
	lda	$gp, 0($gp)			!gpdisp!1
	mtpr	$gp, ptPgp

	lda	$sp, stack+STACK_SIZE($gp)	!gprel

	// Disable interrupts; kernel mode
	lda	t0, IPL_K_HIGH
	mtpr	t0, qemu_ps

	// Make sure kernel entry points are invalid.
	lda	t0, -1
	mtpr	t0, ptEntUna
	mtpr	t0, ptEntIF
	mtpr	t0, ptEntSys
	mtpr	t0, ptEntInt
	mtpr	t0, ptEntArith
	mtpr	t0, ptEntMM

	// Load boot arguments
	mfpr	a0, qemu_trap_arg0
	mfpr	a1, qemu_trap_arg1
	mfpr	a2, qemu_trap_arg2

	// Continue in do_start, outside PALmode.
	ldah	$27, do_start($gp)		!gprelhigh
	lda	$27, do_start($27)		!gprellow
	hw_ret	($27)
ENDFN	__start

/*
 * Machine Check
 *
 * INPUT PARAMETERS:
 * 
 *	trap_arg0 = 
 *	trap_arg1 = 
 *	trap_arg2 = 
 */
	.org	0x0080
Pal_Mchk:
	mfpr	p5, ptMces		// Get the error summary
	or	p5, MCES_M_MIP, p4	// Set machine-check-in-progress
	zap	p4, 0x3c, p4		// Clear space for MCHK and SCB
	mtpr	p4, ptMces

	ldah	p0, SCB_Q_PROCMCHK
	or	p4, p0, p4		// Merge in the SCB vector
	lda	p0, MCHK_K_PROC_HERR
	sll	p0, PT16_V_MCHK, p0
	or	p4, p0, p4		// Merge in the MCHK code
	mtpr	p4, ptMisc

	br	MchkCommon_SaveRegs
ENDFN	Pal_Mchk

/*
 * Interrupt
 *
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = interrupt type
 *	trap_arg1 = UNDEFINED
 *	trap_arg2 = UNDEFINED
 */ 
	.org	0x0100
	.type	Pal_Interrupt, @function
Pal_Interrupt:
	mfpr	p6, qemu_exc_addr
	mfpr	p0, qemu_ps

	STACK_FRAME p0, p6, p2, 0

	mov	IPL_K_HIGH, p0		// Raise IPL
	mtpr	p0, qemu_ps

	mfpr	p0, ptEntInt
	mfpr	$gp, ptKgp
	mfpr    a0, qemu_trap_arg0
	hw_ret	(p0)
ENDFN	Pal_Interrupt

/*
 * Memory Fault
 *
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = faulting address
 *	trap_arg1 = fault type (TNV, ACV, FOR, FOW, FOE)
 *	trap_arg2 = access type (exec=-1, read=0, write=1)
 */ 
	.org	0x0180
Pal_MMFault:
	mfpr	p0, qemu_ps
	mfpr	p6, qemu_exc_addr
	blbs	p6, MchkBugCheck

	STACK_FRAME p0, p6, p2, 1

	mfpr	p0, ptEntMM
	mfpr	$gp, ptKgp
	mfpr	a0, qemu_trap_arg0
	mfpr	a1, qemu_trap_arg1
	mfpr	a2, qemu_trap_arg2
	hw_ret	(p0)
ENDFN	Pal_MMFault

/*
 * Unaligned Data
 * 
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = faulting address
 *	trap_arg1 = opcode of faulting insn
 *	trap_arg2 = src/dst register number
 */ 
	.org	0x0200
Pal_Unalign:
	mfpr	p0, qemu_ps
	mfpr	p6, qemu_exc_addr
	addq	p6, 4, p1		// increment past the faulting insn
	blbs	p6, MchkBugCheck

	STACK_FRAME p0, p1, p2, 1

	mfpr	p0, ptEntUna
	mfpr	$gp, ptKgp
	mfpr	a0, qemu_trap_arg0
	mfpr	a1, qemu_trap_arg1
	mfpr	a2, qemu_trap_arg2
	hw_ret	(p0)
ENDFN	Pal_Unalign

/*
 * Illegal Opcode
 *
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = UNDEFINED
 *	trap_arg1 = UNDEFINED
 *	trap_arg2 = UNDEFINED
 *
 * OUTPUT PARAMETERS:
 *
 *	r16 (a0) = Instruction fault code
 *	r17 (a1) = UNPREDICTABLE
 *	r18 (a2) = UNPREDICTABLE
 */ 
	.org	0x0280
Pal_OpcDec:
	mfpr	p0, qemu_ps
	mfpr	p6, qemu_exc_addr
	addq	p6, 4, p1		// increment past the faulting insn
	blbs	p6, MchkBugCheck

	STACK_FRAME p0, p1, p2, 1

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_OPCDEC, a0
	hw_ret	(p0)
ENDFN	Pal_OpcDec

/*
 * Arithmetic Trap
 *
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = exception type
 *	trap_arg1 = register modification mask
 *	trap_arg2 = UNDEFINED
 */
	.org	0x0300
Pal_Arith:
	mfpr	p0, qemu_ps
	mfpr	p6, qemu_exc_addr
	blbs	p6, MchkBugCheck

	STACK_FRAME p0, p6, p2, 1

	mfpr	p0, ptEntArith
	mfpr	$gp, ptKgp
	mfpr	a0, qemu_trap_arg0
	mfpr	a1, qemu_trap_arg1
	hw_ret	(p0)
ENDFN	Pal_Arith

/*
 * Floating Point Disabled
 *
 * INPUT PARAMETERS:
 *
 *	trap_arg0 = UNDEFINED
 *	trap_arg1 = UNDEFINED
 *	trap_arg2 = UNDEFINED
 *
 * OUTPUT PARAMETERS:
 *
 *	r16 (a0) = Instruction fault code
 *	r17 (a1) = UNPREDICTABLE
 *	r18 (a2) = UNPREDICTABLE
 */ 
	.org	0x0380
Pal_Fen:
	mfpr	p0, qemu_ps
	mfpr	p6, qemu_exc_addr
	blbs	p6, MchkBugCheck

	STACK_FRAME p0, p6, p2, 1

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_FEN, a0
	hw_ret	(p0)
ENDFN	Pal_Fen

/*
 * OSF/1 Privileged CALL_PAL Entry Points
 */

#define ORG_CALL_PAL_PRIV(X)	.org	0x1000+64*X

/*
 * Halt
 *
 * SIDE EFFECTS:
 *
 *	We either power down the system or re-enter the console.
 *	But given that we're not returning to the kernel, there's
 *	no reason to continue processing in assembler.  Go to C.
 */
	ORG_CALL_PAL_PRIV(0x00)
CallPal_Halt:
	bsr	p7, UpdatePCB		// Save kernel data
	lda	v0, HLT_K_SW_HALT

	ldah	p0, 1			// Store 0xdead into CIA RESET reg
	lda	p0, -(0x10000 - 0xdead)(p0)
	lda	p1, 0x878
	sll	p1, 28, p1
	lda	p1, 0x900(p1)
	stl_p	p0, 0(p1)

	br	Sys_EnterConsole
ENDFN	CallPal_Halt

/*
 * Cache Flush
 *
 * For QEMU, this is of course a no-op.
 */
	ORG_CALL_PAL_PRIV(0x01)
CallPal_Cflush:
	hw_rei
ENDFN	CallPal_Cflush

/*
 * Drain Aborts
 *
 * For QEMU, this is of course a no-op.
 */
        ORG_CALL_PAL_PRIV(0x02)
CallPal_Draina:
	hw_rei
ENDFN	CallPal_Draina

	ORG_CALL_PAL_PRIV(0x03)
CallPal_OpcDec03:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec03

	ORG_CALL_PAL_PRIV(0x04)
CallPal_OpcDec04:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec04

	ORG_CALL_PAL_PRIV(0x05)
CallPal_OpcDec05:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec05

	ORG_CALL_PAL_PRIV(0x06)
CallPal_OpcDec06:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec06

	ORG_CALL_PAL_PRIV(0x07)
CallPal_OpcDec07:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec07

	ORG_CALL_PAL_PRIV(0x08)
CallPal_OpcDec08:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec08

/*
 * Console Service
 * 
 * INPUT PARAMETERS:
 * 
 *	r0 (v0)           = Option selector
 *	r16..r21 (a0..a5) = Implementation specific entry parameters
 * 
 * SIDE EFFECTS:
 *
 *	Registers a0..a5, and v0 are UNPREDICTABLE upon return.
 */ 
	ORG_CALL_PAL_PRIV(0x09)
CallPal_Cserve:
	br	Sys_Cserve
ENDFN	CallPal_Cserve

/*
 * Swap PALcode
 *
 * FUNCTIONAL DESCRIPTION:
 *
 *	The swap PALcode (swppal) function replaces the current 
 *	(active) PALcode by the specified new PALcode image.  
 *	This function is intended for use by operating systems 
 *	only during bootstraps and restarts, or during transitions 
 *	to console I/O mode.
 * 
 *	The PALcode descriptor passed in a0 is interpreted as
 *	either a PALcode variant or the base physical address
 *	of the new PALcode image.  If a variant, the PALcode
 *	image must have been previously loaded.  No PALcode
 *	loading occurs as a result of this function. 
 *
 *	NOTE:
 *	This implementation of SWPPAL does not support PALcode
 *	variants.  If a variant is specified in a0, a check is
 *	performed to determine whether the variant is OSF/1 or
 *	not and the returned status is either unknown variant
 *	(if not OSF/1) or variant not loaded.
 *
 * INPUT PARAMETERS:
 *
 *	r16 (a0) = New PALcode variant or base physical address
 *	r17 (a1) = New PC
 *	r18 (a2) = New PCB
 *	r19 (a3) = New VptPtr
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = Returned status indicating:
 *			0 - Success (PALcode was switched)
 *			1 - Unknown PALcode variant
 *			2 - Known PALcode variant, but PALcode not loaded
 *
 *	r26 (ra) = r27 (pv) = New PC
 *		Note that this is non-architected, but is relied on by
 *		the usage of SwpPal within our own console code in order
 *		to simplify its use within C code.
 *
 */
	ORG_CALL_PAL_PRIV(0x0A)
CallPal_SwpPal:
	// Save a copy of the return address in case of machine check.
	mfpr	p6, qemu_exc_addr

	// Accept swapping to OSF PALcode.  The side effect here is to
	// load the other parameters for the kernel.
	cmpeq	a0, 2, v0
	bne	v0, CallPal_SwpPal_Cont

	// Return as an unknown PALcode variant
	mov	1, v0
	hw_rei
ENDFN	CallPal_SwpPal

	.text	1
CallPal_SwpPal_Cont:
	rpcc	p0
	mtpr	a2, ptPcbb
	mtpr	a3, qemu_vptptr

	ldq_p	$sp, PCB_Q_KSP(a2)
	ldq_p	t0, PCB_Q_USP(a2)
	ldq_p	t1, PCB_Q_PTBR(a2)
	ldl_p	t2, PCB_L_PCC(a2)
	ldq_p	t3, PCB_Q_UNIQUE(a2)
	ldq_p	t4, PCB_Q_FEN(a2)

	mtpr	t0, ptUsp

	sll	t1, VA_S_OFF, t1
	mtpr	t1, qemu_ptbr

	subl	t2, p0, t2
	mtpr	t2, qemu_pcc_ofs

	mtpr	t3, qemu_unique

	and	t4, 1, t4
	mtpr	t4, qemu_fen

	mtpr	$31, qemu_tbia		// Flush TLB for new PTBR

	mov	a1, $26
	mov	a1, $27
	hw_ret	(a1)
ENDFN	CallPal_SwpPal_Cont
	.previous

	ORG_CALL_PAL_PRIV(0x0B)
CallPal_OpcDec0B:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec0B

	ORG_CALL_PAL_PRIV(0x0C)
CallPal_OpcDec0C:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec0C

/*
 * Write Interprocessor Interrupt Request
 *
 * INPUT PARAMETERS:
 *
 *	r16 (a0) = target processor number 
 * 
 * OUTPUT PARAMETERS:
 *
 * SIDE EFFECTS:
 * 
 */ 
        ORG_CALL_PAL_PRIV(0x0D)
CallPal_WrIpir:
	// We do not currently support more cpus
	hw_rei
ENDFN	CallPal_WrIpir

	ORG_CALL_PAL_PRIV(0x0E)
CallPal_OpcDec0E:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec0E

	ORG_CALL_PAL_PRIV(0x0F)
CallPal_OpcDec0F:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec0F

/*
 * Read Machine Check Error Summary
 *
 * INPUT PARAMETERS:
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = returned MCES value
 * 
 * SIDE EFFECTS:
 *
 */ 
        ORG_CALL_PAL_PRIV(0x10)
CallPal_RdMces:
	mfpr	v0, ptMces		// Get current MCES value
	and	v0, MCES_M_ALL, v0	// Clear all other bits
	hw_rei
ENDFN	CallPal_RdMces

/*
 * Write Machine Check Error Summary
 *
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = MCES<DPC> <- a0<3>,  MCES<DSC> <- a0<4>
 * 
 * OUTPUT PARAMETERS:
 *
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x11)
CallPal_WrMces:
	// Clear MIP, SCE, PCE
	and	a0, (MCES_M_MIP | MCES_M_SCE | MCES_M_PCE), p0
	mfpr	p1, ptMces
	bic	p1, p0, p1

	// Copy DPC and DSC
	and	a0, (MCES_M_DPC | MCES_M_DSC), p0
	bic	p1, (MCES_M_DPC | MCES_M_DSC), p1
	or	p1, p0, p1

	mtpr	p1, ptMces
	hw_rei
ENDFN	CallPal_WrMces

	ORG_CALL_PAL_PRIV(0x12)
CallPal_OpcDec12:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec12

	ORG_CALL_PAL_PRIV(0x13)
CallPal_OpcDec13:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec13

	ORG_CALL_PAL_PRIV(0x14)
CallPal_OpcDec14:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec14

	ORG_CALL_PAL_PRIV(0x15)
CallPal_OpcDec15:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec15

	ORG_CALL_PAL_PRIV(0x16)
CallPal_OpcDec16:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec16

	ORG_CALL_PAL_PRIV(0x17)
CallPal_OpcDec17:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec17

	ORG_CALL_PAL_PRIV(0x18)
CallPal_OpcDec18:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec18

	ORG_CALL_PAL_PRIV(0x19)
CallPal_OpcDec19:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec19

	ORG_CALL_PAL_PRIV(0x1A)
CallPal_OpcDec1A:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1A

	ORG_CALL_PAL_PRIV(0x1B)
CallPal_OpcDec1B:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1B

	ORG_CALL_PAL_PRIV(0x1C)
CallPal_OpcDec1C:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1C

	ORG_CALL_PAL_PRIV(0x1D)
CallPal_OpcDec1D:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1D

	ORG_CALL_PAL_PRIV(0x1E)
CallPal_OpcDec1E:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1E

	ORG_CALL_PAL_PRIV(0x1F)
CallPal_OpcDec1F:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec1F

	ORG_CALL_PAL_PRIV(0x20)
CallPal_OpcDec20:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec20

	ORG_CALL_PAL_PRIV(0x21)
CallPal_OpcDec21:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec21

	ORG_CALL_PAL_PRIV(0x22)
CallPal_OpcDec22:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec22

	ORG_CALL_PAL_PRIV(0x23)
CallPal_OpcDec23:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec23

	ORG_CALL_PAL_PRIV(0x24)
CallPal_OpcDec24:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec24

	ORG_CALL_PAL_PRIV(0x25)
CallPal_OpcDec25:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec25

	ORG_CALL_PAL_PRIV(0x26)
CallPal_OpcDec26:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec26

	ORG_CALL_PAL_PRIV(0x27)
CallPal_OpcDec27:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec27

	ORG_CALL_PAL_PRIV(0x28)
CallPal_OpcDec28:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec28

	ORG_CALL_PAL_PRIV(0x29)
CallPal_OpcDec29:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec29

	ORG_CALL_PAL_PRIV(0x2A)
CallPal_OpcDec2A:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec2A

/*
 * Write Floating Point Enable
 *
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = ICSR<FPE> <- a0<0>
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x2B)
CallPal_WrFen:
	mfpr	p0, ptPcbb		// Get PCBB
	and	a0, 1, a0		// Clean new FEN value to single bit
	mtpr	a0, qemu_fen
	stl_p	a0, PCB_Q_FEN(p0)	// Write new PCB<FEN>
	hw_rei
ENDFN	CallPal_WrFen

	ORG_CALL_PAL_PRIV(0x2C)
CallPal_OpcDec2C:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec2C

/*
 * Write Virtual Page Table Pointer
 *
 * INPUT PARAMETERS:
 *
 *	r16 (a0) = New virtual page table pointer 
 *
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x2D)
CallPal_WrVptPtr:
	mtpr	a0, qemu_vptptr
	hw_rei
ENDFN	CallPal_WrVptPtr

	ORG_CALL_PAL_PRIV(0x2E)
CallPal_OpcDec2E:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec2E

	ORG_CALL_PAL_PRIV(0x2F)
CallPal_OpcDec2F:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec2F

/*
 * Swap Process Context
 *
 * FUNCTIONAL DESCRIPTION:
 *
 *	The swap process context (swpctx) function saves 
 *	the current process data in the current PCB, then 
 *	switches to the PCB passed in a0 and loads the
 *	new process context.  The old PCB is returned in v0.	
 * 
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New PCBB 
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0  (v0) = Old PCBB
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
	ORG_CALL_PAL_PRIV(0x30)
CallPal_SwpCtx:
	rpcc	p5			// Get cycle counter
	mfpr	p6, qemu_exc_addr	// Save exc_addr for machine check

	mfpr	v0, ptPcbb		// Get current PCBB
	mtpr	a0, ptPcbb		// Save new PCBB
	srl	p5, 32, p7		// Move CC<OFFSET> to low longword

	addl	p5, p7, p7		// Accumulate time for old pcb
	stl_p	p7, PCB_L_PCC(v0)

	ldl_p	t9, PCB_L_PCC(a0)	// Get new PCC
	subl	t9, p5, p5		// Generate and ...
	mtpr	p5, qemu_pcc_ofs	// .. set new CC<OFFSET> bits

	stq_p	$sp, PCB_Q_KSP(v0)	// Store old kernel stack pointer
	mfpr	t10, ptUsp		// Save old user stack pointer
	stq_p	t10, PCB_Q_USP(v0)

	br	CallPal_SwpCtx_Cont
ENDFN	CallPal_SwpCtx

	.text	1
CallPal_SwpCtx_Cont:
	ldq_p	$sp, PCB_Q_KSP(v0)	// Install new stack pointers
	ldq_p	t10, PCB_Q_USP(v0)
	mtpr	t10, ptUsp

	mfpr	t10, qemu_unique	// Save old unique value
	stq_p	t10, PCB_Q_UNIQUE(v0)
	ldq_p	t10, PCB_Q_UNIQUE(a0)	// Install new unique value
	mtpr	t10, qemu_unique

	ldq_p	t8, PCB_Q_FEN(a0)	// Install new FEN
	and	t8, 1, t8
	mtpr	t8, qemu_fen

	// QEMU does not implement an ASN; skip that.

	ldq_p	t10, PCB_Q_PTBR(a0)	// Install new page tables
	sll	t10, VA_S_OFF, t10
	mtpr	t10, qemu_ptbr
	mtpr	$31, qemu_tbia		// Flush TLB, since we don't do ASNs

	hw_rei
ENDFN	CallPal_SwpCtx_Cont
	.previous

/*
 * Write System Value
 *
 * INPUT PARAMETERS:
 *
 *	r16 (a0) = New system value 
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x31)
CallPal_WrVal:
	mtpr	a0, ptSysVal
	hw_rei
ENDFN	CallPal_WrVal

/*
 * Read System Value
 *
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = Returned system value
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0 and t8..t11 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x32)
CallPal_RdVal:
	mfpr	v0, ptSysVal
	hw_rei
ENDFN	CallPal_RdVal

/*
 * Translation Buffer Invalidate
 * 
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = tbi selector type:
 *
 *		-2 - Flush all TB entries (tbia)
 *		-1 - Invalidate all TB entries with ASM=0 (tbiap)
 *		 1 - Invalidate ITB entry for va=a1 (tbisi)
 *		 2 - Invalidate DTB entry for va=a1 (tbisd)
 *		 3 - Invalidate both ITB and DTB entry for va=a1 (tbis)
 *
 *	r17 (a1) = VA for TBISx types
 *
 * Qemu does not implement ASNs or split I/D tlbs.  Therefore these
 * collapse to tbia and tbis.
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x33)
CallPal_Tbi:
	bge	a0, 1f

	mtpr	$31, qemu_tbia
	hw_rei

1:	mtpr	a1, qemu_tbis
	hw_rei
ENDFN	CallPal_Tbi

/*
 * Write System Entry Address
 *
 * INPUT PARAMETERS:
 *
 *	r16 (a0) = VA of system entry point
 *	r17 (a1) = System entry point selector 
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0..a1 are UNPREDICTABLE
 *	upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x34)
CallPal_WrEnt:
	andnot	a0, 3, a0		// Clean PC<1:0>

	cmpult	a1, 6, t8		// Bound the input
	cmoveq	t8, 6, a1

	br	t0, 1f
1:	lda	t0, WrEnt_Table-1b(t0)
	s8addq	a1, t0, t0
	jmp	$31, (t0), 0
ENDFN	CallPal_WrEnt

	.text	1
WrEnt_Table:
0:	mtpr	a0, ptEntInt
	hw_rei
1:	mtpr	a0, ptEntArith
	hw_rei
2:	mtpr	a0, ptEntMM
	hw_rei
3:	mtpr	a0, ptEntIF
	hw_rei
4:	mtpr	a0, ptEntUna
	hw_rei
5:	mtpr	a0, ptEntSys
	hw_rei
6:	nop
	hw_rei
ENDFN	WrEnt_Table
	.previous

/*
 * Swap Interrupt Priority Level
 * 
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New IPL
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0  (v0) = Old IPL
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x35)
CallPal_SwpIpl:
	mfpr	v0, qemu_ps
	and	a0, PS_M_IPL, a0
	and	v0, PS_M_IPL, v0
	mtpr	a0, qemu_ps
	hw_rei
ENDFN	CallPal_SwpIpl

/*
 * Read Processor Status
 *
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = Current PS
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x36)
CallPal_RdPs:
	mfpr	v0, qemu_ps
	hw_rei
ENDFN	CallPal_RdPs

/*
 * Write Kernel Global Pointer
 *
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New KGP value
 *
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x37)
CallPal_WrKgp:
	mtpr	a0, ptKgp
	hw_rei
ENDFN	CallPal_WrKgp

/*
 * Write User Stack Pointer
 * 
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New user stack pointer value
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x38)
CallPal_WrUsp:
	mtpr	a0, ptUsp
	hw_rei
ENDFN	CallPal_WrUsp

/*
 * Write Performance Monitor
 *
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New user stack pointer value
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, t8..t11, and a0 are UNPREDICTABLE upon return.
 */
	ORG_CALL_PAL_PRIV(0x39)
CallPal_WrPerfMon:
	// Not implemented
	hw_rei
ENDFN	CallPal_WrPerfMon

/*
 * Read User Stack Pointer
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = User stack pointer value
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0, and t8..t11 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x3A)
CallPal_RdUsp:
	mfpr	v0, ptUsp
	hw_rei
ENDFN	CallPal_RdUsp

	ORG_CALL_PAL_PRIV(0x3B)
CallPal_OpcDec3B:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec3B

/*
 * Who Am I
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = Current processor number
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0 and t8..t11 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x3C)
CallPal_Whami:
	// We do not currently support more cpus
	mov	0, v0
	hw_rei
ENDFN	CallPal_Whami

/*
 * Return From System Call
 *
 * INPUT PARAMETERS:
 * 
 *	r30 (sp) = Pointer to the top of the kernel stack
 * 
 * OUTPUT PARAMETERS:
 *
 *	r29 (gp) = Restored user mode global pointer
 *	r30 (sp) = User stack pointer
 * 
 * SIDE EFFECTS:
 *
 *	Registers t0 and t8..t11 are UNPREDICTABLE upon return.
 */ 
        ORG_CALL_PAL_PRIV(0x3D)
CallPal_RetSys:
	ldq	t9, FRM_Q_PC($sp)	// Pop the return address
	ldq	$gp, FRM_Q_GP($sp)	// Get the user mode global pointer
	lda	t8, FRM_K_SIZE($sp)
	mtpr	t8, ptKsp

	mov	PS_K_USER, t8		// Set new mode to user
	mtpr	t8, qemu_ps

	mfpr	$sp, ptUsp		// Get the user stack pointer

	andnot	t9, 3, t9		// Clean return PC<1:0>
	hw_ret	(t9)
ENDFN	CallPal_RetSys

/*
 * Wait For Interrupt
 *
 * FUNCTIONAL DESCRIPTION:
 *
 *	If possible, wait for the first of either of the following
 *	conditions before returning: any interrupt other than a clock
 *	tick; or the first clock tick after a specified number of clock
 *	ticks have bbeen skipped.
 *
 * INPUT PARAMETERS:
 * 
 *	???
 * 
 * OUTPUT PARAMETERS:
 *
 *	???
 * 
 * SIDE EFFECTS:
 *
 *	???
 */
	ORG_CALL_PAL_PRIV(0x3E)
CallPal_WtInt:
	hw_rei
ENDFN	CallPal_WtInt

/*
 * Return From Trap, Fault, or Interrupt
 *
 * INPUT PARAMETERS:
 * 
 *	r30 (sp) = Pointer to the top of the kernel stack
 * 
 * OUTPUT PARAMETERS:
 *
 *	ps       <- (sp+00)
 *	pc       <- (sp+08)
 *	r29 (gp) <- (sp+16)
 *	r16 (a0) <- (sp+24)
 *	r17 (a1) <- (sp+32)
 *	r18 (a2) <- (sp+40)
 */ 
        ORG_CALL_PAL_PRIV(0x3F)
CallPal_Rti:
	mfpr	p6, qemu_exc_addr	// Save exc_addr for machine check

	ldq	p4, FRM_Q_PS($sp)	// Get the PS
	ldq	p5, FRM_Q_PC($sp)	// Get the return PC
	ldq	$gp, FRM_Q_GP($sp)	// Get gp
	ldq	a0, FRM_Q_A0($sp)	// Get a0

	ldq	a1, FRM_Q_A1(p7)	// Get a1
	ldq	a2, FRM_Q_A2(p7)	// Get a2
	lda	$sp, FRM_K_SIZE($sp)	// Pop the stack
	bic	p5, 3, p5		// Clean return PC<1:0>

	and	p4, PS_M_CM, p3
	bne	p3, CallPal_Rti_ToUser

	and	p4, PS_M_IPL, p4
	mtpr	p4, qemu_ps
	hw_ret	(p5)
ENDFN	CallPal_Rti

	.text	1
CallPal_Rti_ToUser:
	mtpr	p4, qemu_ps
	mtpr	$sp, ptKsp
	mfpr	$sp, ptUsp
	hw_ret	(p5)
ENDFN	CallPal_Rti_ToUser
	.previous


/*
 * OSF/1 Unprivileged CALL_PAL Entry Points
 */

#define ORG_CALL_PAL_UNPRIV(X)	.org	0x2000+64*(X-0x80)

/*
 * A helper routine for the unprivaledged kernel entry points, since the
 * actual stack frame setup code is just a tad too large to fit inline.
 *
 * INPUT PARAMETERS:
 *
 *	p5 = ps
 *	p6 = exc_addr
 *	p7 = return address
 *
 * SIDE EFFECTS:
 *
 *	p0 is clobbered
 *
 */
	.text	1
CallPal_Stack_Frame:
	// Test if we're currently in user mode
	and	p5, PS_M_CM, p0
	beq	p0, 0f
CallPal_Stack_Frame_FromUser:
	// Switch to kernel mode
	mtpr	$31, qemu_ps
	mtpr	$sp, ptUsp
	mfpr	$sp, ptKsp
0:
	// Allocate the stack frame
	lda	$sp, -FRM_K_SIZE($sp)
	stq	p5, FRM_Q_PS($sp)
	stq	p6, FRM_Q_PC($sp)
	stq	$gp, FRM_Q_GP($sp)
	stq	a0, FRM_Q_A0($sp)
	stq	a1, FRM_Q_A1($sp)
	stq	a2, FRM_Q_A2($sp)
	ret	$31, (p7), 0
ENDFN	CallPal_Stack_Frame
	.previous

/*
 * Breakpoint Trap
 *
 * OUTPUT PARAMETERS:
 *
 *	r16 (a0) = Code for bpt (0)
 *	r17 (a1) = UNPREDICTABLE
 *	r18 (a2) = UNPREDICTABLE
 */ 
        ORG_CALL_PAL_UNPRIV(0x80)
CallPal_Bpt:
	mfpr	p5, qemu_ps
	mfpr	p6, qemu_exc_addr
	bsr	p7, CallPal_Stack_Frame

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_BPT, a0
	hw_ret	(p0)
ENDFN	CallPal_Bpt

/*
 * Bugcheck Trap
 * 
 * OUTPUT PARAMETERS:
 *
 *	r16 (a0) = Code for bugchk (1)
 *	r17 (a1) = UNPREDICTABLE
 *	r18 (a2) = UNPREDICTABLE
 */ 
        ORG_CALL_PAL_UNPRIV(0x81)
CallPal_BugChk:
	mfpr	p5, qemu_ps
	mfpr	p6, qemu_exc_addr
	bsr	p7, CallPal_Stack_Frame

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_BUGCHK, a0
	hw_ret	(p0)
ENDFN	CallPal_BugChk


	ORG_CALL_PAL_UNPRIV(0x82)
CallPal_OpcDec82:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec82

/*
 * System Call
 */ 
        ORG_CALL_PAL_UNPRIV(0x83)
CallPal_CallSys:
	mfpr	p5, qemu_ps
	mfpr	p6, qemu_exc_addr

	and	p5, PS_M_CM, p0
	beq	p0, 0f

	bsr	p7, CallPal_Stack_Frame_FromUser

	mfpr	p0, ptEntSys
	mfpr	$gp, ptKgp
	hw_ret	(p0)

0:	subq	p6, 4, p6		// Get PC of CALL_PAL insn
	br	MchkOSBugCheck
ENDFN	CallPal_CallSys

	ORG_CALL_PAL_UNPRIV(0x84)
CallPal_OpcDec84:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec84

	ORG_CALL_PAL_UNPRIV(0x85)
CallPal_OpcDec85:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec85


/*
 * I-Stream Memory Barrier
 *
 * For QEMU, this is of course a no-op.
 */ 
        ORG_CALL_PAL_UNPRIV(0x86)
CallPal_Imb:
	hw_rei
ENDFN	CallPal_Imb


	ORG_CALL_PAL_UNPRIV(0x87)
CallPal_OpcDec87:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec87

	ORG_CALL_PAL_UNPRIV(0x88)
CallPal_OpcDec88:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec88

	ORG_CALL_PAL_UNPRIV(0x89)
CallPal_OpcDec89:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec89

	ORG_CALL_PAL_UNPRIV(0x8A)
CallPal_OpcDec8A:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8A

	ORG_CALL_PAL_UNPRIV(0x8B)
CallPal_OpcDec8B:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8B

	ORG_CALL_PAL_UNPRIV(0x8C)
CallPal_OpcDec8C:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8C

	ORG_CALL_PAL_UNPRIV(0x8D)
CallPal_OpcDec8D:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8D

	ORG_CALL_PAL_UNPRIV(0x8E)
CallPal_OpcDec8E:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8E

	ORG_CALL_PAL_UNPRIV(0x8F)
CallPal_OpcDec8F:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec8F

	ORG_CALL_PAL_UNPRIV(0x90)
CallPal_OpcDec90:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec90

	ORG_CALL_PAL_UNPRIV(0x91)
CallPal_OpcDec91:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec91

	ORG_CALL_PAL_UNPRIV(0x92)
CallPal_OpcDec92:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec92

	ORG_CALL_PAL_UNPRIV(0x93)
CallPal_OpcDec93:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec93

	ORG_CALL_PAL_UNPRIV(0x94)
CallPal_OpcDec94:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec94

	ORG_CALL_PAL_UNPRIV(0x95)
CallPal_OpcDec95:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec95

	ORG_CALL_PAL_UNPRIV(0x96)
CallPal_OpcDec96:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec96

	ORG_CALL_PAL_UNPRIV(0x97)
CallPal_OpcDec97:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec97

	ORG_CALL_PAL_UNPRIV(0x98)
CallPal_OpcDec98:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec98

	ORG_CALL_PAL_UNPRIV(0x99)
CallPal_OpcDec99:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec99

	ORG_CALL_PAL_UNPRIV(0x9A)
CallPal_OpcDec9A:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec9A

	ORG_CALL_PAL_UNPRIV(0x9B)
CallPal_OpcDec9B:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec9B

	ORG_CALL_PAL_UNPRIV(0x9C)
CallPal_OpcDec9C:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec9C

	ORG_CALL_PAL_UNPRIV(0x9D)
CallPal_OpcDec9D:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDec9D

/*
 * Read Unique Value
 * 
 * OUTPUT PARAMETERS:
 *
 *	r0 (v0) = Returned process unique value
*/ 
        ORG_CALL_PAL_UNPRIV(0x9E)
CallPal_RdUnique:
	mfpr	v0, qemu_unique
	hw_rei
ENDFN	CallPal_RdUnique

/*
 * Write Unique Value
 * 
 * INPUT PARAMETERS:
 * 
 *	r16 (a0) = New process unique value
 */ 
        ORG_CALL_PAL_UNPRIV(0x9F)
CallPal_WrUnique:
	mtpr	a0, qemu_unique
	hw_rei
ENDFN	CallPal_WrUnique

	ORG_CALL_PAL_UNPRIV(0xA0)
CallPal_OpcDecA0:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA0

	ORG_CALL_PAL_UNPRIV(0xA1)
CallPal_OpcDecA1:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA1

	ORG_CALL_PAL_UNPRIV(0xA2)
CallPal_OpcDecA2:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA2

	ORG_CALL_PAL_UNPRIV(0xA3)
CallPal_OpcDecA3:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA3

	ORG_CALL_PAL_UNPRIV(0xA4)
CallPal_OpcDecA4:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA4

	ORG_CALL_PAL_UNPRIV(0xA5)
CallPal_OpcDecA5:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA5

	ORG_CALL_PAL_UNPRIV(0xA6)
CallPal_OpcDecA6:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA6

	ORG_CALL_PAL_UNPRIV(0xA7)
CallPal_OpcDecA7:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA7

	ORG_CALL_PAL_UNPRIV(0xA8)
CallPal_OpcDecA8:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA8

	ORG_CALL_PAL_UNPRIV(0xA9)
CallPal_OpcDecA9:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecA9

/*
 * Generate Trap
 *
 * OUTPUT PARAMETERS:
 *
 *	r16 (a0) = Code for gentrap (2)
 *	r17 (a1) = UNPREDICTABLE
 *	r18 (a2) = UNPREDICTABLE
 */ 
        ORG_CALL_PAL_UNPRIV(0xAA)
CallPal_GenTrap:
	mfpr	p5, qemu_ps
	mfpr	p6, qemu_exc_addr
	bsr	p7, CallPal_Stack_Frame

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_GENTRAP, a0
	hw_ret	(p0)
ENDFN	CallPal_GenTrap

	ORG_CALL_PAL_UNPRIV(0xAB)
CallPal_OpcDecAB:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecAB

	ORG_CALL_PAL_UNPRIV(0xAC)
CallPal_OpcDecAC:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecAC

	ORG_CALL_PAL_UNPRIV(0xAD)
CallPal_OpcDecAD:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecAD

	ORG_CALL_PAL_UNPRIV(0xAE)
CallPal_OpcDecAE:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecAE

	ORG_CALL_PAL_UNPRIV(0xAF)
CallPal_OpcDecAF:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecAF

	ORG_CALL_PAL_UNPRIV(0xB0)
CallPal_OpcDecB0:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB0

	ORG_CALL_PAL_UNPRIV(0xB1)
CallPal_OpcDecB1:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB1

	ORG_CALL_PAL_UNPRIV(0xB2)
CallPal_OpcDecB2:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB2

	ORG_CALL_PAL_UNPRIV(0xB3)
CallPal_OpcDecB3:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB3

	ORG_CALL_PAL_UNPRIV(0xB4)
CallPal_OpcDecB4:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB4

	ORG_CALL_PAL_UNPRIV(0xB5)
CallPal_OpcDecB5:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB5

	ORG_CALL_PAL_UNPRIV(0xB6)
CallPal_OpcDecB6:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB6

	ORG_CALL_PAL_UNPRIV(0xB7)
CallPal_OpcDecB7:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB7

	ORG_CALL_PAL_UNPRIV(0xB8)
CallPal_OpcDecB8:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB8

	ORG_CALL_PAL_UNPRIV(0xB9)
CallPal_OpcDecB9:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecB9

	ORG_CALL_PAL_UNPRIV(0xBA)
CallPal_OpcDecBA:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecBA

	ORG_CALL_PAL_UNPRIV(0xBB)
CallPal_OpcDecBB:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecBB

	ORG_CALL_PAL_UNPRIV(0xBC)
CallPal_OpcDecBC:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecBC

	ORG_CALL_PAL_UNPRIV(0xBD)
CallPal_OpcDecBD:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecBD

	ORG_CALL_PAL_UNPRIV(0xBE)
CallPal_OpcDecBE:
	br	CallPal_OpcDec
ENDFN	CallPal_OpcDecBE

	ORG_CALL_PAL_UNPRIV(0xBF)
CallPal_OpcDec:
	mfpr	p5, qemu_ps
	mfpr	p6, qemu_exc_addr
	bsr	p7, CallPal_Stack_Frame

	mfpr	p0, ptEntIF
	mfpr	$gp, ptKgp
	mov	IF_K_OPCDEC, a0
	hw_ret	(p0)
ENDFN	CallPal_OpcDec

	.org	0x3000
	.text	1
/*
 * PALcode detected processor machine check handler.
 *
 *      The PALcode-detected machine check handler loads a code
 *      indicating the type of machine check error, loads 
 *      the System Control Block (SCB) vector for the 
 *      processor machine check service routine, sets the 
 *      Machine-Check-In-Progress (MIP) flag in the Machine
 *      Check Error Summary register (MCES), and merges
 *      with the common machine check flow.
 *
 *      If a second processor machine check error condition 
 *      is detected while the MIP flag is set, the processor 
 *      is forced into console I/O mode indicating "double 
 *      error abort encountered" as the reason for the halt. 
 * 
 * CALLING SEQUENCE:
 * 
 *      Called when an internal processor error is detected
 *      that cannot be successfully corrected by hardware or
 *      PALcode.
 * 
 * INPUT PARAMETERS:
 *
 *      r14 (p6) = Exception address 
 * 
 * OUTPUT PARAMETERS:
 *
 *      ptMchk0         = saved v0
 *      ptMchk1         = saved t0
 *      ptMchk2         = saved t3
 *      ptMchk3         = saved t4
 *      ptMchk4         = saved t5
 *	ptMchk5		= saved exc_addr
 *      ptMisc<47:32>   = MCHK code
 *      ptMisc<31:16>   = SCB vector
 *      ptMces<MIP>     = Set
 * 
 * SIDE EFFECTS:
 *
 *      r0 (v0), r1 (t0), and r4..r6 (t3..t5) are saved in
 *      PAL temporaries and are available for use as scratch
 *      registers by the system specific machine check 
 *      handler.
 */

MchkBugCheck:
        lda     p7, MCHK_K_BUGCHECK
        br      1f
MchkOSBugCheck:
        lda     p7, MCHK_K_OS_BUGCHECK
1:      sll     p7, PT16_V_MCHK, p7	// Move error code into upper longword

	mfpr	p4, ptMces		// Get and isolate MCES bits
	zap	p4, 0x3c, p4
	or	p4, p7, p4		// Combine MCES and error code

	ldah	p7, SCB_Q_PROCMCHK	// Combine SCB and MCHK bits
	or	p4, p7, p7
	or	p7, MCES_M_MIP, p7	// Set machine-check-in-progress
	mtpr	p7, ptMces

MchkCommon_SaveRegs:
	mtpr	v0, ptMchk0		// Save temporaries
	mtpr	t0, ptMchk1
	mtpr	t3, ptMchk2
	mtpr	t4, ptMchk3
	mtpr	t5, ptMchk4
	mtpr	p6, ptMchk5		// Save the exception address

	blbs	p4, MchkDouble
	blbs	p6, MchkFromPal
ENDFN	MchkBugCheck

/*
 * Common Machine Check Handler
 *
 * INPUT STATE:
 *
 *      ptMchk0		Saved v0
 *      ptMchk1		Saved t0
 *      ptMchk2		Saved t3
 *      ptMchk3		Saved t4
 *      ptMchk4		Saved t5
 *      ptMchk5		Saved exc_addr
 *      ptMisc<47:32>	MCHK code
 *      ptMisc<31:16>	SCB vector
 *      ptMces<MIP>	Set
 *
 * Registers v0, t0, and t3 .. t5 are available for use, in
 * addition to the shadow registers.
 */

MchkCommon:
	mov	0, t4			// Assume non-retryable.

	mfpr	t5, ptMisc		// Load MCHK code
	extwl	t5, 4, t5
	andnot	t5, 1, t5
ENDFN	MchkCommon

/*
 * Build Machine Check Logout Frame
 *
 *      This portion of the  machine check handler builds a logout frame
 *      in the PAL impure scratch area, builds a stack frame on the kernel
 *      stack (already built if there was an interrupt machine check),
 *      loads the GP with the KGP, loads the machine check entry 
 *      code in a0, loads a platform-specific interrupt vector 
 *      (typically the same value as the SCB offset) in a1, loads 
 *      the kseg address of the logout area in a2, and dispatches 
 *      to the kernel interrupt handler pointed to by the entInt 
 *      operating system entry point.
 *
 * OUTPUT PARAMETERS:
 * 
 *      a0 (r16) = Machine check entry type
 *      a1 (r17) = Platform-specific interrupt vector
 *      a2 (r18) = Pointer to logout area
 */

.macro	STORE_IPR	which, offset, base
	mfpr	v0, \which
	stq_p	v0, \offset(\base)
.endm

MchkLogOut:
	mfpr	p6, ptPgp		// Get address of logout frame
	lda	p6, laf_base(p6)	!gprel

	lda	t3, $laf_size
	stl_p	t3, laf_l_size - laf_base(p6)
	stl_p	t4, laf_l_flag - laf_base(p6)

	lda	t3, laf_cpu_base - laf_base
	stl_p	t3, laf_l_cpu - laf_base(p6)
	lda	t3, laf_sys_base - laf_base
	stl_p	t3, laf_l_sys - laf_base(p6)

	STORE_IPR  qemu_shadow0, laf_q_shadow - laf_base + 0x00, p6
	STORE_IPR  qemu_shadow1, laf_q_shadow - laf_base + 0x08, p6
	STORE_IPR  qemu_shadow2, laf_q_shadow - laf_base + 0x10, p6
	STORE_IPR  qemu_shadow3, laf_q_shadow - laf_base + 0x18, p6
	STORE_IPR  qemu_shadow4, laf_q_shadow - laf_base + 0x20, p6
	STORE_IPR  qemu_shadow5, laf_q_shadow - laf_base + 0x28, p6
	STORE_IPR  qemu_shadow6, laf_q_shadow - laf_base + 0x30, p6
	STORE_IPR  qemu_shadow7, laf_q_shadow - laf_base + 0x38, p6

	STORE_IPR  pt0, laf_q_pt - laf_base + 0x00, p6
	STORE_IPR  pt1, laf_q_pt - laf_base + 0x08, p6
	STORE_IPR  pt2, laf_q_pt - laf_base + 0x10, p6
	STORE_IPR  pt3, laf_q_pt - laf_base + 0x18, p6
	STORE_IPR  pt4, laf_q_pt - laf_base + 0x20, p6
	STORE_IPR  pt5, laf_q_pt - laf_base + 0x28, p6
	STORE_IPR  pt6, laf_q_pt - laf_base + 0x30, p6
	STORE_IPR  pt7, laf_q_pt - laf_base + 0x38, p6
	STORE_IPR  pt8, laf_q_pt - laf_base + 0x40, p6
	STORE_IPR  pt9, laf_q_pt - laf_base + 0x48, p6
	STORE_IPR pt10, laf_q_pt - laf_base + 0x50, p6
	STORE_IPR pt11, laf_q_pt - laf_base + 0x58, p6
	STORE_IPR pt12, laf_q_pt - laf_base + 0x60, p6
	STORE_IPR pt13, laf_q_pt - laf_base + 0x68, p6
	STORE_IPR pt14, laf_q_pt - laf_base + 0x70, p6
	STORE_IPR pt15, laf_q_pt - laf_base + 0x78, p6
	STORE_IPR pt16, laf_q_pt - laf_base + 0x80, p6
	STORE_IPR pt17, laf_q_pt - laf_base + 0x88, p6
	STORE_IPR pt18, laf_q_pt - laf_base + 0x90, p6
	STORE_IPR pt19, laf_q_pt - laf_base + 0x98, p6
	STORE_IPR pt20, laf_q_pt - laf_base + 0xa0, p6
	STORE_IPR pt21, laf_q_pt - laf_base + 0xa8, p6
	STORE_IPR pt22, laf_q_pt - laf_base + 0xb0, p6
	STORE_IPR pt23, laf_q_pt - laf_base + 0xb8, p6

	mfpr	t0, ptMchk1
	mfpr	t3, ptMchk2
	mfpr	t4, ptMchk3
	mfpr	t5, ptMchk4
	mfpr	p7, ptMchk5
	stq_p	p7, laf_q_exc_addr - laf_base(p6)

	stq_p	$31, laf_q_exc_sum - laf_base(p6)
	stq_p	$31, laf_q_exc_mask - laf_base(p6)

	STORE_IPR qemu_palbr, laf_q_pal_base - laf_base, p6

	stq_p	$31, laf_q_isr - laf_base(p6)
	stq_p	$31, laf_q_icsr - laf_base(p6)
	stq_p	$31, laf_q_icperr - laf_base(p6)
	stq_p	$31, laf_q_dcperr - laf_base(p6)
	stq_p	$31, laf_q_va - laf_base(p6)
	stq_p	$31, laf_q_mm_stat - laf_base(p6)
	stq_p	$31, laf_q_sc_addr - laf_base(p6)
	stq_p	$31, laf_q_sc_stat - laf_base(p6)
	stq_p	$31, laf_q_bc_addr - laf_base(p6)
	stq_p	$31, laf_q_ei_addr - laf_base(p6)
	stq_p	$31, laf_q_fill_syndrome - laf_base(p6)
	stq_p	$31, laf_q_ei_stat - laf_base(p6)

	STORE_IPR qemu_lock_addr, laf_q_ld_lock - laf_base, p6

	// bsr v0, Sys_MchkLogOut

	mfpr	v0, ptMchk0

	// Build the stack frame on the kernel stack and post the interrupt
	mfpr	p7, ptMisc
	extwl	p7, 4, p7
	mov	p6, p4			// Stash pointer to logout
	lda	a1, SCB_Q_SYSMCHK
	blbs	p7, 0f			// Check if stack frame already built

	mfpr	p5, qemu_ps
	mfpr	p6, ptMchk5		// Reload exc_addr for double mchk

	STACK_FRAME	p5, p6, p7, 0

	mov	IPL_K_MCHK, p5		// Raise IPL
	mtpr	p5, qemu_ps

	mfpr	a1, ptMisc		// Isolate SCB vector
	extwl	a1, 2, a1

0:	mfpr	p7, ptEntInt
	lda	a0, INT_K_MCHK

	lda	a2, -1			// Load kseg offset
	srl	a2, VA_S_SIZE-1, a2
	sll	a2, VA_S_SIZE-1, a2
	addq	a2, p4, a2		// Pass ptr to logout area

	mfpr	$gp, ptKgp
	hw_ret	(p7)
ENDFN	MchkLogOut

MchkDouble:
	bsr	p7, UpdatePCB
	lda	v0, HLT_K_DBL_MCHK
	br	Sys_EnterConsole
ENDFN	MchkDouble

MchkFromPal:
	bsr	p7, UpdatePCB
	lda	v0, HLT_K_MCHK_FROM_PAL
	br	Sys_EnterConsole
ENDFN	MchkFromPal

MchkKspInvalid:
	bsr	p7, UpdatePCB
	lda	v0, HLT_K_KSP_INVAL
	br	Sys_EnterConsole
ENDFN	MchkKspInvalid

/*
 * Update the current PCB with new SP and CC info.
 *
 * INPUT PARAMETERS:
 *
 *	p7	= return linkage
 */

UpdatePCB:
	rpcc	p5
	mfpr	p4, ptPcbb

	mfpr	p3, qemu_ps		// Check current mode
	and	p3, PS_M_CM, p3
	beq	p3, 1f

	mtpr	$sp, ptUsp		// Save user stack pointer
	stq_p	$sp, PCB_Q_USP(p4)
	br	2f

1:	mtpr	$sp, ptKsp		// Save kernel stack pointer
	stq_p	$sp, PCB_Q_KSP(p4)

2:	srl	p5, 32, p3		// Merge for new time
	addl	p5, p3, p3
	stl_p	p3, PCB_L_PCC(p4)	// Store new time

	mfpr	p5, qemu_unique		// Save unique
	stq_p	p5, PCB_Q_UNIQUE(p4)

	ret	$31, (p7), 0
ENDFN	UpdatePCB

/*
 * FIXME
 */
Sys_EnterConsole:
Sys_Cserve:
	halt

/*
 * Allocate the logout frame.
 */
	.section	.sbss
	.type	laf_base,@object
	.align	3
laf_base:
laf_l_size:		.long	0
laf_l_flag:		.long	0
laf_l_cpu:		.long	0
laf_l_sys:		.long	0
laf_q_mchk_code:	.quad	0

$las_size		= . - laf_base

laf_cpu_base:
laf_q_shadow:		.skip	8*8
laf_q_pt:		.skip	8*24
laf_q_exc_addr:		.quad	0
laf_q_exc_sum:		.quad	0
laf_q_exc_mask:		.quad	0
laf_q_pal_base:		.quad	0
laf_q_isr:		.quad	0
laf_q_icsr:		.quad	0
laf_q_icperr:		.quad	0
laf_q_dcperr:		.quad	0
laf_q_va:		.quad	0
laf_q_mm_stat:		.quad	0
laf_q_sc_addr:		.quad	0
laf_q_sc_stat:		.quad	0
laf_q_bc_addr:		.quad	0
laf_q_ei_addr:		.quad	0
laf_q_fill_syndrome:	.quad	0
laf_q_ei_stat:		.quad	0
laf_q_ld_lock:		.quad	0

laf_sys_base:
laf_q_cpu_err0:		.quad	0
laf_q_cpu_err1:		.quad	0
laf_q_cia_err:		.quad	0
laf_q_err_mask:		.quad	0
laf_q_cia_syn:		.quad	0
laf_q_mem_err0:		.quad	0
laf_q_mem_err1:		.quad	0
laf_q_pci_err0:		.quad	0
laf_q_pci_err1:		.quad	0
laf_q_pci_err2:		.quad	0

$laf_size		= . - laf_base
	.size	laf_base, . - laf_base

	.align 3
	.globl	stack
	.type	stack,@object
	.size	stack,STACK_SIZE
stack:	.skip	STACK_SIZE

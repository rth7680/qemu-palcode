#include "pal.h"
#include SYSTEM_H

/*
 * Sys_Setup
 *
 * Do any system specific setup necessary.
 *
 * INPUT PARAMETERS
 *
 *	r16 (a0) = whami
 *	r26 (ra) = return address
 */
	.globl	Sys_Setup
	.ent	Sys_Setup
Sys_Setup:
	.frame	$sp, 0, p7, 0
	lda		t0, TYPHOON_CCHIP_DIM0
	lda		t1, TYPHOON_CCHIP_DIM2
	lda		t2, TYPHOON_CCHIP_IIC0
	lda		t3, TYPHOON_CCHIP_IIC2
	and		a0, 2, t4
	cmovne		t4, t1, t0
	cmovne		t4, t3, t2
	and		a0, 1, t4
	sll		t4, 6, t4
	addq		t0, t4, t0
	addq		t2, t4, t2
	LOAD_PHYS_CCHIP	t4
	addq		t0, t4, t0
	addq		t2, t4, t2
	mtpr		t0, ptCpuDIR
	mtpr		t2, ptCpuIIC
	ret
	.end	Sys_Setup

/*
 * Cserve_Ena
 *
 * Unmask a PCI interrupt
 */
	.globl	Cserve_Ena
Cserve_Ena:
	// FIXME
	hw_rei
ENDFN	Cserve_Ena

/*
 * Cserve_Dis
 *
 * Mask a PCI interrupt
 */
	.globl	Cserve_Dis
Cserve_Dis:
	// FIXME
	hw_rei
ENDFN	Cserve_Dis

/*
 * inb
 *
 * Read a byte from the PCI I/O bus.
 */
	.globl	inb
	.ent	inb
inb:
	.frame	$sp, 0, $26, 0
	.prologue 0
	LOAD_KSEG_PCI_IO v0
	addq	v0, a0, v0
	ldbu	v0, 0(v0)
	ret
	.end	inb

/*
 * outb
 *
 * Write a byte to the PCI I/O bus.
 */
	.globl	outb
	.ent	outb
outb:
	.frame	$sp, 0, $26, 0
	.prologue 0
	LOAD_KSEG_PCI_IO p0
	addq	p0, a1, p0
	stb	a0, 0(p0)
	ret
	.end	outb


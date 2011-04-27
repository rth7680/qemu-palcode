#ifndef SYS_SX164_H
#define SYS_SX164_H 1

#include "core_cia.h"

#ifdef __ASSEMBLER__

.macro	SYS_ACK_CLK	t0, t1, t2
	LOAD_KSEG_PCI_IO \t0		// Set RTCADD (0x70) to index reg 0xC
	mov	0xc, \t1
	stb	\t1, 0x70(\t0)
	ldbu	\t1, 0x71(\t0)		// Read RTCDAT to clear interrupt
.endm

.macro	SYS_DEV_VECTOR	ret
	FIXME
.endm

#endif /* ASSEMBLER */

#define SYS_TYPE	ST_DEC_EB164
#define SYS_VARIATION	(15 << 10)
#define SYS_REVISION	0

#endif /* SYS_SX164_H */

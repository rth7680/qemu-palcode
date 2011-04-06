/*
 *  Virtual Address Options: 8K byte page size
 */
#define VA_S_SIZE       43
#define VA_S_OFF        13
#define VA_S_SEG        10
#define VA_S_PAGE_SIZE  8192

/*
**  System Entry Instruction Fault (entIF) Constants:
*/

#define IF_K_BPT        0x0
#define IF_K_BUGCHK     0x1
#define IF_K_GENTRAP    0x2
#define IF_K_FEN        0x3
#define IF_K_OPCDEC     0x4

/*
**  System Entry Hardware Interrupt (entInt) Constants:
*/

#define INT_K_IP	0x0
#define INT_K_CLK	0x1
#define INT_K_MCHK	0x2
#define INT_K_DEV	0x3
#define INT_K_PERF	0x4

/*
**  System Entry MM Fault (entMM) Constants:
*/

#define	MM_K_TNV	0x0
#define MM_K_ACV	0x1
#define MM_K_FOR	0x2
#define MM_K_FOE	0x3
#define MM_K_FOW	0x4

/*
**  Processor Status Register (PS) Bit Summary
**
**      Extent  Size    Name    Function
**      ------  ----    ----    ---------------------------------
**        <3>    1      CM      Current Mode
**      <2:0>    3      IPL     Interrupt Priority Level
*/

#define PS_V_CM         3
#define PS_M_CM         (1<<PS_V_CM)
#define PS_V_IPL        0
#define PS_M_IPL        (7<<PS_V_IPL)

#define PS_K_KERN       (0<<PS_V_CM)
#define PS_K_USER       (1<<PS_V_CM)

#define IPL_K_ZERO      0x0
#define IPL_K_SW0       0x1
#define IPL_K_SW1       0x2
#define IPL_K_DEV0      0x3
#define IPL_K_DEV1      0x4
#define IPL_K_CLK       0x5
#define IPL_K_RT        0x6
#define IPL_K_PERF      0x6
#define IPL_K_PFAIL     0x6
#define IPL_K_MCHK      0x7

#define IPL_K_LOW       0x0
#define IPL_K_HIGH      0x7


/*
**  Process Control Block (PCB) Offsets:
*/

#define PCB_Q_KSP	0x0000
#define PCB_Q_USP	0x0008
#define PCB_Q_PTBR	0x0010
#define PCB_L_PCC	0x0018
#define PCB_L_ASN	0x001C
#define PCB_Q_UNIQUE	0x0020
#define PCB_Q_FEN	0x0028
#define PCB_Q_RSV0	0x0030
#define PCB_Q_RSV1	0x0038

/*
**  Stack Frame (FRM) Offsets:
**
**  There are two types of system entries for OSF/1 - those for the
**  callsys CALL_PAL function and those for exceptions and interrupts.
**  Both entry types use the same stack frame layout.  The stack frame
**  contains space for the PC, the PS, the saved GP, and the saved
**  argument registers a0, a1, and a2.  On entry, SP points to the
**  saved PS.
*/

#define	FRM_Q_PS	0
#define FRM_Q_PC	8
#define FRM_Q_GP	16
#define FRM_Q_A0	24
#define FRM_Q_A1	32
#define FRM_Q_A2	40

#define FRM_K_SIZE	48

/*
**  Halt Codes:
*/

#define HLT_K_RESET	    0x0000
#define HLT_K_HW_HALT	    0x0001
#define HLT_K_KSP_INVAL	    0x0002
#define HLT_K_SCBB_INVAL    0x0003
#define HLT_K_PTBR_INVAL    0x0004
#define HLT_K_SW_HALT	    0x0005
#define HLT_K_DBL_MCHK	    0x0006
#define HLT_K_MCHK_FROM_PAL 0x0007

/*
**  Machine Check Codes:
*/

#define MCHK_K_TPERR	    0x0080
#define MCHK_K_TCPERR	    0x0082
#define MCHK_K_HERR	    0x0084
#define MCHK_K_ECC_C	    0x0086
#define MCHK_K_ECC_NC	    0x0088
#define MCHK_K_UNKNOWN	    0x008A
#define MCHK_K_CACKSOFT	    0x008C
#define MCHK_K_BUGCHECK	    0x008E
#define MCHK_K_OS_BUGCHECK  0x0090
#define MCHK_K_DCPERR	    0x0092
#define MCHK_K_ICPERR	    0x0094
#define MCHK_K_RETRY_IRD    0x0096
#define MCHK_K_PROC_HERR    0x0098

/*
** System Machine Check Codes:
*/

#define MCHK_K_READ_NXM     0x0200
#define MCHK_K_SYS_HERR     0x0202

/*
**  Machine Check Error Status Summary (MCES) Register Format
**
**	 Extent	Size	Name	Function
**	 ------	----	----	---------------------------------
**	  <0>	  1	MIP	Machine check in progress
**	  <1>	  1	SCE	System correctable error in progress
**	  <2>	  1	PCE	Processor correctable error in progress
**	  <3>	  1	DPC	Disable PCE error reporting
**	  <4>	  1	DSC	Disable SCE error reporting
*/

#define MCES_V_MIP	0
#define MCES_M_MIP	(1<<MCES_V_MIP)
#define MCES_V_SCE	1
#define MCES_M_SCE	(1<<MCES_V_SCE)
#define MCES_V_PCE	2
#define MCES_M_PCE	(1<<MCES_V_PCE)
#define MCES_V_DPC	3
#define MCES_M_DPC	(1<<MCES_V_DPC)
#define MCES_V_DSC	4
#define MCES_M_DSC	(1<<MCES_V_DSC)

#define MCES_M_ALL      (MCES_M_MIP | MCES_M_SCE | MCES_M_PCE | MCES_M_DPC \
                         | MCES_M_DSC)

/*
**
**   Miscellaneous PAL State Flags (ptMisc) Bit Summary
**
**       Extent Size  Name      Function
**       ------ ----  ----      ---------------------------------
**       <55:48>  8   SWAP      Swap PALcode flag -- character 'S'
**       <47:32> 16   MCHK      Machine Check Error code
**       <31:16> 16   SCB       System Control Block vector
**       <15:08>  8   WHAMI     Who-Am-I identifier
**       <04:00>  5   MCES      Machine Check Error Summary bits
**
*/

#define PT16_V_MCES     0
#define PT16_V_WHAMI    8
#define PT16_V_SCB      16
#define PT16_V_MCHK     32
#define PT16_V_SWAP     48

/*
**  Who-Am-I (WHAMI) Register Format
**
**	 Extent	Size	Name	Function
**	 ------	----	----	---------------------------------
**	  <7:0>	  8	ID	Who-Am-I identifier
**	  <15:8>   1	SWAP	Swap PALcode flag - character 'S'
*/

#define WHAMI_V_SWAP	8
#define WHAMI_M_SWAP	(1<<WHAMI_V_SWAP)
#define WHAMI_V_ID	0
#define WHAMI_M_ID	0xFF

#define WHAMI_K_SWAP    0x53    /* Character 'S' */

/* System Control Block stuff.  */
#define SCB_Q_SYSMCHK           0x0660
#define SCB_Q_PROCMCHK          0x0670


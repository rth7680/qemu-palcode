#include <string.h>
#include <stddef.h>
#include "hwrpb.h"
#include "osf.h"
#include "uart.h"
#include SYSTEM_H

#define PAGE_SHIFT	13
#define PAGE_SIZE	(1ul << PAGE_SHIFT)
#define PAGE_OFFSET	0xfffffc0000000000UL

#define VPTPTR		0xfffffffe00000000UL

#define PA(VA)		((unsigned long)(VA) & 0xfffffffffful)
#define VA(PA)		((void *)(PA) + PAGE_OFFSET)

#define HZ	1024

struct hwrpb_combine {
  struct hwrpb_struct hwrpb;
  struct percpu_struct processor;
  struct memdesc_struct md;
  struct memclust_struct mc[2];
};

extern char stack[PAGE_SIZE] __attribute__((section(".sbss")));
extern char _end[] __attribute__((visibility("hidden"), nocommon));

struct pcb_struct pcb __attribute__((section(".sbss")));

static unsigned long page_dir[1024] __attribute__((aligned(PAGE_SIZE)));

/* The HWRPB must be aligned because it is exported at INIT_HWRPB.  */
struct hwrpb_combine hwrpb __attribute__((aligned(PAGE_SIZE)));

static void *last_alloc;

static void *
alloc (unsigned long size, unsigned long align)
{
  void *p = (void *)(((unsigned long)last_alloc + align - 1) & ~(align - 1));
  last_alloc = p + size;
  return memset (p, 0, size);
}

static inline unsigned long
pt_index(unsigned long addr, int level)
{
  return (addr >> (PAGE_SHIFT + (10 * level))) & 0x3ff;
}

static inline unsigned long
build_pte (void *page)
{
  unsigned long bits;

  bits = PA((unsigned long)page) << (32 - PAGE_SHIFT);
  bits += _PAGE_VALID | _PAGE_KRE | _PAGE_KWE;

  return bits;
}

static inline void *
pte_page (unsigned long pte)
{
  return VA(pte >> 32 << PAGE_SHIFT);
}

static void
set_pte (unsigned long addr, void *page)
{
  unsigned long *pt = page_dir;
  unsigned long index;

  index = pt_index(addr, 2);
  if (pt[index] != 0)
    pt = pte_page (pt[index]);
  else
    {
      unsigned long *npt = alloc(PAGE_SIZE, PAGE_SIZE);
      pt[index] = build_pte (npt);
      pt = npt;
    }

  index = pt_index(addr, 1);
  if (pt[index] != 0)
    pt = pte_page (pt[index]);
  else
    {
      unsigned long *npt = alloc(PAGE_SIZE, PAGE_SIZE);
      pt[index] = build_pte (npt);
      pt = npt;
    }

  index = pt_index(addr, 0);
  pt[index] = build_pte (page);
}

static void
init_page_table(void)
{
  /* Install the self-reference for the virtual page table base register.  */
  page_dir[pt_index(VPTPTR, 2)] = build_pte(page_dir);

  set_pte ((unsigned long)INIT_HWRPB, &hwrpb);
  
  /* ??? SRM maps some amount of memory at 0x20000000 for use by programs
     started from the console prompt.  Including the bootloader.  While
     we're emulating MILO, don't bother as we jump straight to the kernel
     loaded into KSEG.  */
}

static inline unsigned long
init_cpuid (void)
{
  unsigned long implver, amask;

  implver = __builtin_alpha_implver();
  amask = ~__builtin_alpha_amask(-1);

  switch (implver)
    {
    case 0: /* EV4 */
      return EV4_CPU;

    case 1: /* EV5 */
      if ((amask & 0x101) == 0x101)	/* MAX + BWX */
	return PCA56_CPU;
      if (amask & 1)			/* BWX */
	return EV56_CPU;
      return EV5_CPU;

    case 2: /* EV6 */
      if (amask & 4)			/* CIX */
	return EV67_CPU;
      return EV6_CPU;
    }
    return 0;
}

static void
init_hwrpb (unsigned long memsize)
{
  unsigned long pal_pages;
  unsigned long cpu_type;
  
  hwrpb.hwrpb.phys_addr = PA(&hwrpb);

  /* Yes, the 'HWRPB' magic is in big-endian byte ordering.  */
  hwrpb.hwrpb.id = ( (long)'H' << 56
		   | (long)'W' << 48
		   | (long)'R' << 40
		   | (long)'P' << 32
		   | (long)'B' << 24);

  hwrpb.hwrpb.size = sizeof(struct hwrpb_struct);

  /* The inclusion of MILO here tells the Linux kernel that we do
     not (yet) support any of the extended console support routines
     that are in SRM.  */
  ((int *)hwrpb.hwrpb.ssn)[0] = ( 'M' << 0
				| 'I' << 8
				| 'L' << 16
				| 'O' << 24);
  ((int *)hwrpb.hwrpb.ssn)[1] = ( ' ' << 0
				| 'Q' << 8
				| 'E' << 16
				| 'M' << 24);
  ((int *)hwrpb.hwrpb.ssn)[2] = ( 'U' << 0);

  /* For now, hard-code emulation of sx164.  */
  cpu_type = init_cpuid();
  hwrpb.hwrpb.cpuid = cpu_type;
  hwrpb.hwrpb.pagesize = PAGE_SIZE;
  hwrpb.hwrpb.pa_bits = 40;
  hwrpb.hwrpb.max_asn = 127;
  hwrpb.hwrpb.sys_type = SYS_TYPE;
  hwrpb.hwrpb.sys_variation = SYS_VARIATION;
  hwrpb.hwrpb.sys_revision = SYS_REVISION;
  hwrpb.processor.type = cpu_type;

  hwrpb.hwrpb.intr_freq = HZ * 4096;
  hwrpb.hwrpb.cycle_freq = 250000000;	/* QEMU architects 250MHz.  */

  hwrpb.hwrpb.vptb = VPTPTR;

  hwrpb.hwrpb.nr_processors = 1;
  hwrpb.hwrpb.processor_size = sizeof(struct percpu_struct);
  hwrpb.hwrpb.processor_offset = offsetof(struct hwrpb_combine, processor);

  hwrpb.hwrpb.mddt_offset = offsetof(struct hwrpb_combine, md);
  hwrpb.md.numclusters = 2;

  pal_pages = (PA(last_alloc) + PAGE_SIZE - 1) >> PAGE_SHIFT;

  hwrpb.mc[0].numpages = pal_pages;
  hwrpb.mc[0].usage = 1;
  hwrpb.mc[1].start_pfn = pal_pages;
  hwrpb.mc[1].numpages = (memsize >> PAGE_SHIFT) - pal_pages;

  {
    unsigned long sum = 0, *l;
    for (l = (unsigned long *) &hwrpb.hwrpb; l < &hwrpb.hwrpb.chksum; ++l)
      sum += *l;
    hwrpb.hwrpb.chksum = sum;
  }
}

static void
init_pcb (void)
{
  pcb.ksp = (unsigned long)stack + sizeof(stack);
  pcb.ptbr = PA(page_dir) >> PAGE_SHIFT;
  pcb.flags = 1; /* FEN */
}

void
do_hello(void)
{
  uart_puts(COM1, "Hello, World!\n");
  asm ("halt");
  __builtin_unreachable ();
}

void
do_start(unsigned long memsize, void (*kernel_entry)(void), long cpus)
{
  last_alloc = _end;

  init_page_table();
  init_hwrpb(memsize);
  init_pcb();
  uart_init();

  {
    register int variant __asm__("$16") = 2;	/* OSF/1 PALcode */
    register void (*pc)(void) __asm__("$17");
    register unsigned long pa_pcb __asm__("$18");
    register unsigned long vptptr __asm__("$19");

    pc = (kernel_entry ? kernel_entry : do_hello);
    pa_pcb = PA(&pcb);
    vptptr = VPTPTR;
    asm("call_pal 0x0a" : : "r"(variant), "r"(pc), "r"(pa_pcb), "r"(vptptr));
  }
  __builtin_unreachable ();
}

void
do_start_wait(void)
{
  while (1)
    {
      // WtInt with interrupts off.  Rely on the fact that QEMU will
      // un-halt the CPU when an interrupt arrives.
      asm("lda $16,-1\n\tcall_pal 0x3e" : : : "$0", "$16");

      // FIXME do something with the IPI.
    }
}

#include <string.h>
#include <stddef.h>
#include "hwrpb.h"
#include "osf.h"
#include "uart.h"

#define PAGE_SHIFT	13
#define PAGE_SIZE	(1ul << PAGE_SHIFT)
#define PAGE_OFFSET	0xfffffc0000000000UL

#if 1
#define PA(VA)		((unsigned long)(unsigned int)(VA))
#else
#define PA(VA)		((VA) - PAGE_OFFSET)
#endif
#define VA(PA)		((PA) + PAGE_OFFSET)

#define HZ	1024

struct pcb_struct pal_pcb __attribute__((section(".sbss")));

struct hwrpb_combine {
  struct hwrpb_struct hwrpb;
  struct percpu_struct processor;
  struct memdesc_struct md;
  struct memclust_struct mc[2];
} hwrpb __attribute__((section(".data.hwrpb"))) = {
  /* This is HWRPB\0\0\0.  */
  .hwrpb.id = 0x4857525042000000,

  .hwrpb.size = sizeof(struct hwrpb_struct),
  .hwrpb.pagesize = PAGE_SIZE,
  .hwrpb.ssn = "MILO QEMU",

  /* ??? This should match TARGET_PHYS_ADDR_SPACE_BITS from qemu.  */
  .hwrpb.pa_bits = 44,

  /* ??? Should we be truethful and say 1 asn, or simply pretend we
     have ASNs but ignore them?  */
  .hwrpb.max_asn = 127,

  /* For now, hard-code emulation of sx164.  */
  .hwrpb.cpuid = PCA56_CPU,
  .processor.type = PCA56_CPU,
  .hwrpb.sys_type = ST_DEC_EB164,
  .hwrpb.sys_variation = 15 << 10,
  .hwrpb.sys_revision = 0,

  .hwrpb.intr_freq = HZ * 4096,

  /* ??? What the hell should we put here.  Measure like the kernel will?  */
  .hwrpb.cycle_freq = 400000000,

  .hwrpb.vptb = 0x200000000UL,
  .hwrpb.nr_processors = 1,
  .hwrpb.processor_size = sizeof(struct percpu_struct),
  .hwrpb.processor_offset = offsetof(struct hwrpb_combine, processor),

  .hwrpb.mddt_offset = offsetof(struct hwrpb_combine, md),
  .md.numclusters = 2,
  .mc[0].usage = 2
};

unsigned long page_dir[1024] __attribute__((aligned(PAGE_SIZE)));

extern char _end[];
static unsigned long last_alloc = (unsigned long)_end;

static void *
alloc (unsigned long size, unsigned long align)
{
  unsigned long p = (last_alloc + align - 1) & ~(align - 1);

  last_alloc = p + size;
  return (void *)p;
}

static unsigned long
init_cpuid (void)
{
  unsigned long implver, amask;

  __asm ("implver %0" : "=r"(implver));
  __asm ("amask %1,%0" : "=r"(amask) : "r"(-1));
  amask = ~amask;

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
hwrpb_update_checksum (void)
{
  unsigned long sum = 0, *l;
  for (l = (unsigned long *) &hwrpb.hwrpb; l < &hwrpb.hwrpb.chksum; ++l)
    sum += *l;
  hwrpb.hwrpb.chksum = sum;
}

static void
init_hwrpb (unsigned long memsize)
{
  unsigned long pal_pages;

  hwrpb.hwrpb.phys_addr = PA((unsigned long)&hwrpb);

  pal_pages = (PA(last_alloc) + PAGE_SIZE - 1) >> PAGE_SHIFT;

  hwrpb.mc[0].numpages = pal_pages;
  hwrpb.mc[1].start_pfn = pal_pages;
  hwrpb.mc[1].numpages = (memsize >> PAGE_SHIFT) - pal_pages;

  hwrpb_update_checksum ();
}

static void
init_pcb (void)
{
  pal_pcb.ptbr = PA((unsigned long)page_dir);
  pal_pcb.flags = 1;
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
  return (void *)VA(pte >> 32 << PAGE_SHIFT);
}

static void
set_pte (unsigned long addr, void *page)
{
  unsigned long *pt = page_dir;
  unsigned long index;

  index = (addr >> (PAGE_SHIFT+20)) % 1024;
  if (pt[index] != 0)
    pt = pte_page (pt[index]);
  else
    {
      unsigned long *npt = alloc(PAGE_SIZE, PAGE_SIZE);
      pt[index] = build_pte (npt);
      pt = npt;
    }

  index = (addr >> (PAGE_SHIFT+10)) % 1024;
  if (pt[index] != 0)
    pt = pte_page (pt[index]);
  else
    {
      unsigned long *npt = alloc(PAGE_SIZE, PAGE_SIZE);
      pt[index] = build_pte (npt);
      pt = npt;
    }

  index = (addr >> PAGE_SHIFT) % 1024;
  pt[index] = build_pte (page);
}

static void
init_page_table (unsigned long memsize)
{
  unsigned long i, addr, max_addr, page;

  set_pte ((unsigned long)INIT_HWRPB, &hwrpb);
  
  /* SRM places the self-map for the VPTBR in the second entry.  */
  /* MILO places the self-map for the VPTBR in the last entry.  */
  page_dir[1023] = build_pte (page_dir);

  /* Write the SRM vptptr.  */
  {
    register unsigned long a0 __asm__("$16") = 0xfffffffe00000000UL;
    __asm ("call_pal 0x2d" : : "r"(a0));
  }
}

void
do_start(unsigned long memsize, void (*kernel_entry)(void))
{
  init_page_table (memsize);
  init_hwrpb (memsize);
  init_pcb ();

  uart_init ();
  uart_puts (COM1, "Hello, World!\n");

  if (kernel_entry)
    kernel_entry();
  asm ("halt");
}

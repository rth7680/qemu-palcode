#ifndef PROTOS_H
#define PROTOS_H 1

/* 
 * Cserve functions.
 */

static inline unsigned long ldq_p(unsigned long addr)
{
  register unsigned long v0 __asm__("$0");
  register unsigned long a0 __asm__("$16") = 1;
  register unsigned long a1 __asm__("$17") = addr;

  asm volatile ("call_pal 9"
		: "=r"(v0), "+r"(a0), "+r"(a1) :
		: "$18", "$19", "$20", "$21");

  return v0;
}

static inline unsigned long stq_p(unsigned long port, unsigned long val)
{
  register unsigned long v0 __asm__("$0");
  register unsigned long a0 __asm__("$16") = 4;
  register unsigned long a1 __asm__("$17") = port;
  register unsigned long a2 __asm__("$18") = val;

  asm volatile ("call_pal 9"
		: "=r"(v0), "+r"(a0), "+r"(a1), "+r"(a2) :
		: "$19", "$20", "$21");

  return v0;
}

/*
 * I/O functions
 */

extern unsigned long inb(unsigned long port);
extern unsigned long outb(unsigned char val, unsigned long port);

#endif /* PROTOS_H */

#ifndef IO_H
#define IO_H

#include "cia.h"

static inline unsigned long
inb(unsigned long port)
{
  return *(volatile unsigned char *)(CIA_BW_IO + port);
}

static inline void
outb(unsigned char val, unsigned long port)
{
  *(volatile unsigned char *)(CIA_BW_IO + port) = val;
}

#endif

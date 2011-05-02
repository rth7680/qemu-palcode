/* Declarations common the the C portions of the QEMU PALcode console.

   Copyright (C) 2011 Richard Henderson

   This file is part of QEMU PALcode.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the text
   of the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; see the file COPYING.  If not see
   <http://www.gnu.org/licenses/>.  */

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

/*
 * CRB functions
 */

extern unsigned long crb_dispatch(long select, long a1, long a2,
                                  long a3, long a4);
extern unsigned long crb_fixup(unsigned long vptptr, unsigned long hwrpb);

#endif /* PROTOS_H */

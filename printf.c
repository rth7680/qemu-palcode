/* A reduced version of the printf function.

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

#include <stdarg.h>
#include <stdbool.h>
#include "uart.h"

static int print_decimal(unsigned long val)
{
  char buf[32];
  char *p = buf+31;

  *p = 0;
  if (val == 0)
    *--p = '0';
  else
    {
      do
	{
	  unsigned long d, r;

	  /* Compiling with -Os results in a call to the division routine.
	     Do what the compiler ought to have done.  */
	  d = __builtin_alpha_umulh(val, 0xcccccccccccccccd);
	  d >>= 3;
	  r = val - (d * 10);

	  *--p = r + '0';
	  val = d;
	}
      while (val);
    }

  uart_puts(COM1, p+1);
  return sizeof(buf) - (p - buf);
}

static int print_hex(unsigned long val)
{
  char buf[32];
  char *p = buf+31;

  *p = 0;
  if (val == 0)
    *--p = '0';
  else
    {
      do
	{
	  int d = val % 16;
	  *--p = (d < 10 ? '0' : 'a' - 10) + d;
	  val /= 16;
	}
      while (val);
    }

  uart_puts(COM1, p+1);
  return sizeof(buf) - (p - buf);
}

int printf(const char *fmt, ...)
{
  va_list args;
  unsigned long val;
  int r = 0;

  va_start(args, fmt);

  for (; *fmt ; fmt++)
    if (*fmt != '%')
      {
        uart_putchar(COM1, *fmt);
	r++;
      }
    else
      {
	bool is_long = false;

      restart:
        switch (*++fmt)
	  {
	  case '%':
	    uart_putchar(COM1, '%');
	    r++;
	    break;

	  case 'l':
	    is_long = true;
	    goto restart;

	  case 'd':
	    if (is_long)
	      {
		long d = va_arg (args, long);
		if (d < 0)
		  {
		    uart_putchar(COM1, '-');
		    d = -d;
		  }
		val = d;
	      }
	    else
	      {
		int d = va_arg (args, int);
		if (d < 0)
		  {
		    uart_putchar(COM1, '-');
		    d = -d;
		    r++;
		  }
		val = d;
	      }
	    goto do_unsigned;

	  case 'u':
	    if (is_long)
	      val = va_arg (args, unsigned long);
	    else
	      val = va_arg (args, unsigned int);

	  do_unsigned:
	    r += print_decimal (val);
	    break;

	  case 'x':
	    if (is_long)
	      val = va_arg (args, unsigned long);
	    else
	      val = va_arg (args, unsigned int);
	    r += print_hex (val);

	  case 's':
	    {
	      const char *s = va_arg (args, const char *);
	      while (*s)
		{
		  uart_putchar(COM1, *s++);
		  r++;
		}
	      break;
	    }

	  default:
	    uart_putchar(COM1, '%');
	    uart_putchar(COM1, *fmt);
	    r += 2;
	    break;
	  }
      }

  va_end(args);
  return r;
}

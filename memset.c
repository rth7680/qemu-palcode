void *memset(void *optr, int ival, unsigned long size)
{
  unsigned long val = ival;
  void *ptr = optr;

  if (__builtin_expect (size == 0, 0))
    return optr;

  if (__builtin_expect (val != 0, 0))
    {
      val = val & 0xff;
      val |= val << 8;
      val |= val << 16;
      val |= val << 32;
    }

  if (__builtin_expect ((unsigned long)ptr & 1, 0))
    {
      *(char *)ptr = val;
      ptr += 1;
      size -= 1;
    }

  if (__builtin_expect ((unsigned long)ptr & 2, 0))
    {
      if (size < 2)
	goto tail_1;
      *(short *)ptr = val;
      ptr += 2;
      size -= 2;
    }

  if (__builtin_expect ((unsigned long)ptr & 4, 0))
    {
      if (size < 4)
	goto tail_3;
      *(int *)ptr = val;
      ptr += 4;
      size -= 4;
    }
  
  while (size >= 8)
    {
      *(long *)ptr = val;
      ptr += 8;
      size -= 8;
    }

  if (size >= 4)
    {
      *(int *)ptr = val;
      ptr += 4;
      size -= 4;
    }

 tail_3:
  if (size >= 2)
    {
      *(short *)ptr = val;
      ptr += 2;
      size -= 2;
    }

 tail_1:
  if (size > 0)
    {
      *(char *)ptr = val;
      ptr += 1;
      size -= 1;
    }

  return optr;
}

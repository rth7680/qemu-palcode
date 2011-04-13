CROSS = alphaev67-linux-
CC = $(CROSS)gcc
LD = $(CROSS)ld
CFLAGS = -O -g -msmall-text -msmall-data -fvisibility=hidden \
	-mno-fp-regs -fno-strict-aliasing

OBJS = pal.o init.o uart.o memset.o printf.o

all: palcode

palcode: palcode.ld $(OBJS)
	$(LD) -relax -o $@ -T palcode.ld -Map palcode.map $(OBJS)

clean:
	rm -f *.o
	rm -f palcode palcode.map

pal.o: pal.S osf.h
	$(CC) $(CFLAGS) -c -Wa,-m21264 -Wa,--noexecstack -o $@ $<

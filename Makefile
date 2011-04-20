CROSS = alphaev67-linux-
CC = $(CROSS)gcc
LD = $(CROSS)ld

CFLAGS = -Os -g -Wall -fvisibility=hidden -fno-strict-aliasing \
  -msmall-text -msmall-data -mno-fp-regs -mbuild-constants

CFLAGS += -mcpu=pca56

OBJS = pal.o init.o uart.o memset.o printf.o

all: palcode-sx164

palcode-sx164: palcode.ld $(OBJS)
	$(LD) -relax -o $@ -T palcode.ld -Map $@.map $(OBJS)

clean:
	rm -f *.o
	rm -f palcode palcode.map

pal.o: pal.S osf.h uart.h
	$(CC) $(CFLAGS) -c -Wa,-m21264 -Wa,--noexecstack -o $@ $<

init.o: init.c hwrpb.h osf.h uart.h
printf.o: printf.c uart.h
uart.o: uart.c uart.h io.h cia.h

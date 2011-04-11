CC = /home/rth/work/gcc/run-axp/bin/alphaev6-linux-gcc
LD = /home/rth/work/gcc/run-axp/bin/alphaev6-linux-ld
CFLAGS = -O2 -g -msmall-text -msmall-data -fvisibility=hidden

OBJS = pal.o init.o uart.o memset.o

all: palcode

palcode: palcode.ld $(OBJS)
	$(LD) -relax -o $@ -T palcode.ld -Map palcode.map $(OBJS)

clean:
	rm -f *.o
	rm -f palcode palcode.map

pal.o: pal.S osf.h
	$(CC) $(CFLAGS) -c -Wa,-m21264 -Wa,--noexecstack -o $@ $<

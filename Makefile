CC = /home/rth/work/gcc/run-axp/bin/alphaev6-linux-gcc

all: pal.o

pal.o: pal.S
	$(CC) -c -Wa,-m21264 -g -o $@ $<

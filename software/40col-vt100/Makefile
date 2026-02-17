PLATFORM = replica1

all: tetris.mon 

tetris.mon: tetris
	bintomon -1 -l 0x300 -r 0x300 tetris >tetris.mon

tetris: tetris.c 
	CC65_HOME=/usr/local/share/cc65 cl65 -O -vm -m tetris.map -t $(PLATFORM) tetris.c 

clean:
	$(RM) *.lst *.map *.mon *~





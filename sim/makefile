# Default makefile 
# 24 November 2014
# Kevin Gilbert
# Senior Design

CC=iverilog
CFLAGS=
LDFLAGS=
SOURCES=testbench.v can_sim.v
OBJECTS=$(SOURCES:.c=.o)
EXECUTABLE=sim
LOG=out

all: $(SOURCES) $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@

.cpp.o:
	$(CC) $(CLFAGS) $< -o $@

run:
	vvp $(EXECUTABLE)

log:
	vvp $(EXECUTABLE) > $(LOG)

filter:
	python filter.py
	vim out_node1    

clean: 
	rm -rf *o $(EXECUTABLE)

CC = gcc
CXX = g++
LDLIBS = -lpng -fopenmp
CFLAGS = -lm
VECOPT = -fopt-info-vec-all -march=native
main: CFLAGS += -pthread
CXXFLAGS = $(CFLAGS)
TARGETS = main

.PHONY: all
all: $(TARGETS)

.PHONY: clean
clean:
	rm -f $(TARGETS) $(TARGETS:=.o)

# Boing BASIC - host build (macOS / Linux)
CC      ?= cc
CFLAGS  ?= -O2 -g
WARN     = -std=c99 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare
B        = build
PLAT    ?= posix

RT_SRC   = $(wildcard src/runtime/*.c) $(wildcard src/runtime/a3d/*.c) $(wildcard src/runtime/$(PLAT)/*.c)
CC_SRC   = $(wildcard src/compiler/*.c)
VM_SRC   = $(wildcard src/vm/*.c)
RT_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(RT_SRC))
CC_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(CC_SRC))
VM_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(VM_SRC))
HDRS     = $(wildcard src/runtime/*.h src/runtime/a3d/*.h src/runtime/$(PLAT)/*.h src/compiler/*.h src/compiler/*.def src/vm/*.h)

all: $(B)/boing $(B)/libboing.a $(B)/include/boing.h

$(B)/obj/%.o: src/%.c $(HDRS)
	@mkdir -p $(dir $@)
	$(CC) $(WARN) $(CFLAGS) -c $< -o $@

$(B)/libboing.a: $(RT_OBJ)
	@rm -f $@
	ar rcs $@ $^

$(B)/boing: $(B)/obj/main/main.o $(CC_OBJ) $(VM_OBJ) $(B)/libboing.a
	$(CC) $(CFLAGS) -o $@ $(B)/obj/main/main.o $(CC_OBJ) $(VM_OBJ) $(B)/libboing.a -lm

$(B)/include/boing.h: $(wildcard src/runtime/*.h)
	@mkdir -p $(B)/include
	cp src/runtime/*.h $(B)/include/

test: all
	@sh tools/stackcheck.sh
	@sh tools/os4-build-check.sh
	@for f in tests/c/*.c; do $(CC) $(WARN) $(CFLAGS) -I$(B)/include -o $(B)/ctest_$$(basename $$f .c) $$f $(B)/libboing.a -lm && $(B)/ctest_$$(basename $$f .c) || exit 1; done
	@sh tests/run.sh

clean:
	rm -rf $(B)

.PHONY: all test clean

bench: all
	python3 tools/bench.py $(BENCH_ARGS)

.PHONY: bench

# Boing BASIC - host build (macOS / Linux)
CC      ?= cc
CFLAGS  ?= -O2 -g
WARN     = -std=c99 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare
B        = build
PLAT    ?= posix

RT_SRC   = $(wildcard src/runtime/*.c) $(wildcard src/runtime/a3d/*.c) $(wildcard src/runtime/audio/*.c) $(wildcard src/runtime/$(PLAT)/*.c)
CC_SRC   = $(wildcard src/compiler/*.c)
VM_SRC   = $(wildcard src/vm/*.c)
RT_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(RT_SRC))
CC_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(CC_SRC))
VM_OBJ   = $(patsubst src/%.c,$(B)/obj/%.o,$(VM_SRC))
HDRS     = $(wildcard src/runtime/*.h src/runtime/a3d/*.h src/runtime/audio/*.h src/runtime/$(PLAT)/*.h src/compiler/*.h src/compiler/*.def src/vm/*.h)

all: $(B)/boing $(B)/libboing.a $(B)/include/boing.h

# objects depend on a stamp of the compiler and flags (rewritten only when they change): a build
# with other CFLAGS into the same directory rebuilds everything instead of mixing objects
FLAGS_LINE := $(CC) $(shell $(CC) -dumpversion 2>/dev/null) | $(WARN) $(CFLAGS) | $(PLAT)
$(B)/flags.stamp: FORCE
	@mkdir -p $(B)
	@echo '$(FLAGS_LINE)' | cmp -s - $@ || echo '$(FLAGS_LINE)' > $@
FORCE:

$(B)/obj/%.o: src/%.c $(HDRS) $(B)/flags.stamp
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
	@sh tools/flags-check.sh
	@sh tools/os4-build-check.sh
	@for f in tests/c/*.c; do $(CC) $(WARN) $(CFLAGS) -I$(B)/include -o $(B)/ctest_$$(basename $$f .c) $$f $(B)/libboing.a -lm && $(B)/ctest_$$(basename $$f .c) || exit 1; done
	@sh tests/run.sh
	@python3 tools/test_os4guest.py
	@python3 tools/kit/test_kit_guards.py
	@sh tests/break/run.sh $(CURDIR)/build/boing
	@sh tests/cli/run.sh $(CURDIR)/build/boing
	@sh examples/riffwright/tests/run.sh $(CURDIR)/build/boing
	@sh examples/stack_tower_bb/tools/test.sh
	@sh examples/orbit_docking_bb/tools/test.sh
	@sh examples/ace_pilot2_bb/tools/test.sh
	@sh examples/scairy_fun_bb/tools/test.sh
	@for t in examples/*/tests/host-test.sh; do sh $$t || exit 1; done

clean:
	rm -rf $(B)

.PHONY: all test clean FORCE

bench: all
	python3 tools/bench.py $(BENCH_ARGS)

.PHONY: bench

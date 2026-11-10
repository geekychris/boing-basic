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
# standard extensions linked into the stock interpreter (docs/extensions.md): STD_EXTS=sqlite
# takes $(STD_EXT_DIR)/sqlite/sqlite.c (or .cpp) and its .bbx 'link' libraries. Empty by default,
# so a host build needs no extra libraries; the kit build sets it
STD_EXTS    ?=
STD_EXT_DIR ?= ext
BOING_EXE   ?= $(B)/boing
STDX_SRCS = $(foreach e,$(STD_EXTS),$(firstword $(wildcard $(STD_EXT_DIR)/$(e)/$(e).c $(STD_EXT_DIR)/$(e)/$(e).cpp)))
STDX_OBJS = $(patsubst %,$(B)/obj/stdext/%.o,$(notdir $(STDX_SRCS)))
STDX_LIBS = $(if $(strip $(STD_EXTS)),$(shell sh tools/stdext.sh libs host $(STD_EXT_DIR) $(STD_EXTS)))
STDX_LD   = $(if $(filter %.cpp,$(STDX_SRCS)),$(CXX),$(CC))
EXT_INIT  = $(if $(strip $(STD_EXTS)),$(B)/obj/stdext/glue.o $(STDX_OBJS),$(B)/obj/main/vmext_default.o)
HDRS     = $(wildcard src/runtime/*.h src/runtime/a3d/*.h src/runtime/audio/*.h src/runtime/$(PLAT)/*.h src/compiler/*.h src/compiler/*.def src/vm/*.h)

all: $(B)/boing $(B)/libboing.a $(B)/libboingvm.a $(B)/include/boing.h

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

$(BOING_EXE): $(B)/obj/main/main.o $(EXT_INIT) $(CC_OBJ) $(VM_OBJ) $(B)/libboing.a
	$(if $(strip $(STD_EXTS)),$(STDX_LD),$(CC)) $(CFLAGS) -o $@ $(B)/obj/main/main.o $(EXT_INIT) $(CC_OBJ) $(VM_OBJ) $(B)/libboing.a $(STDX_LIBS) -lm

# STD_EXTS: the glue (regenerated when the list changes) and each extension's object
$(B)/obj/stdext/glue.c: FORCE
	@mkdir -p $(dir $@)
	@sh tools/stdext.sh glue $(STD_EXTS) | cmp -s - $@ || { sh tools/stdext.sh glue $(STD_EXTS) > $@; rm -f $(B)/obj/stdext/glue.o; }
$(B)/obj/stdext/glue.o: $(B)/obj/stdext/glue.c
	$(CC) $(WARN) $(CFLAGS) -c $< -o $@
define stdext_rule
$(B)/obj/stdext/$(notdir $(1)).o: $(1) $(HDRS) $(B)/flags.stamp
	@mkdir -p $(B)/obj/stdext
	$(if $(filter %.cpp,$(1)),$(CXX),$(CC)) $(CFLAGS) -Isrc/runtime -c $(1) -o $$@
endef
$(foreach s,$(STDX_SRCS),$(eval $(call stdext_rule,$(s))))

# the interpreter as a library: `boing vm` links main.o, the compiler and the VM with a program's
# extensions into a custom interpreter (docs/extensions.md)
$(B)/libboingvm.a: $(B)/obj/main/main.o $(B)/obj/main/vmext_default.o $(CC_OBJ) $(VM_OBJ)
	@rm -f $@
	ar rcs $@ $^

$(B)/include/boing.h: $(wildcard src/runtime/*.h)
	@mkdir -p $(B)/include
	cp src/runtime/*.h $(B)/include/

test: all
	@sh tools/stackcheck.sh
	@sh tools/flags-check.sh
	@python3 tools/genmembers.py --check
	@$(B)/boing members > /dev/null || { echo 'boing members: a listed member does not resolve'; exit 1; }
	@sh tools/os4-build-check.sh
	@for f in tests/c/*.c; do $(CC) $(WARN) $(CFLAGS) -I$(B)/include -o $(B)/ctest_$$(basename $$f .c) $$f $(B)/libboing.a -lm && $(B)/ctest_$$(basename $$f .c) || exit 1; done
	@sh tests/run.sh
	@sh tests-net/run.sh $(CURDIR)/build/boing
	@sh tests-net/socket-run.sh $(CURDIR)/build/boing
	@python3 tools/test_os4guest.py
	@python3 tools/kit/test_kit_guards.py
	@sh tests/break/run.sh $(CURDIR)/build/boing
	@sh tests/cli/run.sh $(CURDIR)/build/boing
	@sh tests/ext/run.sh $(CURDIR)/build/boing
	@sh examples/riffwright/tests/run.sh $(CURDIR)/build/boing
	@sh examples/stack_tower_bb/tools/test.sh
	@sh examples/orbit_docking_bb/tools/test.sh
	@sh examples/ace_pilot2_bb/tools/test.sh
	@sh examples/scairy_fun_bb/tools/test.sh
	@for t in examples/*/tests/host-test.sh; do sh $$t || exit 1; done
	@python3 tools/manual-check.py

manual-test: all
	python3 tools/manual-check.py --verbose

clean:
	rm -rf $(B)

.PHONY: all test clean FORCE manual-test

bench: all
	python3 tools/bench.py $(BENCH_ARGS)

.PHONY: bench

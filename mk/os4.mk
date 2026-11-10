# Cross build for AmigaOS 4.1 PPC, run inside the walkero Docker image by tools/build-os4.sh
# (or natively on the Amiga with the SDK's GCC: make -f mk/os4.mk CC=gcc AR=ar).
#
# Never -mcpu=440/440fp: GCC then inlines string functions with dlmzb., which exists only on
# the 440/460 (QEMU's sam460ex) and crashes real X5000/A1222/G4 machines. `make check-cpu`
# verifies the binaries contain none.
CC      ?= ppc-amigaos-gcc
AR      ?= ppc-amigaos-ar
OBJDUMP ?= ppc-amigaos-objdump
ifeq ($(origin CC),default)
CC = ppc-amigaos-gcc
endif
ifeq ($(origin AR),default)
AR = ppc-amigaos-ar
endif
OUT     ?= build/os4
# -Os, not -O2: under QEMU on the sam460ex guest, speed is dominated by TLB refills (a small,
# software-refilled TLB), so code size wins. m1b, VM: Tank Duel 37.4 -> 43.3 fps, late-bound
# calls 34 -> 2.3 us, Chr$ string building 730 -> 35 ms; native games unchanged (docs/performance.md)
CFLAGS  ?= -Os
# no -D__USE_INLINE__: the runtime calls IFace->Function() explicitly
CFLAGS  += -mcrt=newlib -mcpu=powerpc -Wall -Werror=implicit-function-declaration -std=gnu99 -D__USE_OLD_TIMEVAL__ \
           -DBB_PLATFORM_OS4 -Isrc -Isrc/runtime -Isrc/vm -Isrc/compiler
LDFLAGS += -mcrt=newlib -mcpu=powerpc
# pixel loops (Canvas drawing and blits, the Engine3D rasterizer, the audio mixer) stay -O2: with
# -Os they ran 2x slower (Orbit Docking on m1b: blit 2.96 -> 6.38 ms, draw 1.89 -> 2.67 ms)
HOT_OBJS := $(OUT)/obj/runtime/canvas.o $(OUT)/obj/runtime/os4/canvas_os4.o $(OUT)/obj/runtime/engine3d.o \
            $(patsubst src/%.c,$(OUT)/obj/%.o,$(wildcard src/runtime/a3d/*.c)) $(OUT)/obj/runtime/audio/bbmix.o
$(HOT_OBJS): CFLAGS += -O2
LIBS    += -lauto -lm

# libboing: the portable runtime plus the OS4 parts
RT_SRCS   := $(wildcard src/runtime/*.c) $(wildcard src/runtime/a3d/*.c) $(wildcard src/runtime/audio/*.c) $(wildcard src/runtime/os4/*.c)
COMP_SRCS := $(wildcard src/compiler/*.c)
VM_SRCS   := $(wildcard src/vm/*.c)
MAIN_SRCS := $(wildcard src/main/*.c)

obj = $(patsubst src/%.c,$(OUT)/obj/%.o,$(1))
RT_OBJS   := $(call obj,$(RT_SRCS))
TOOL_OBJS := $(call obj,$(COMP_SRCS) $(VM_SRCS) $(MAIN_SRCS))

TEST_SRCS := $(wildcard tests/os4/*.c)
TEST_BINS := $(patsubst tests/os4/%.c,$(OUT)/tests/%,$(TEST_SRCS))

all: $(OUT)/libboing.a $(if $(MAIN_SRCS),$(OUT)/boing $(OUT)/libboingvm.a) $(TEST_BINS)

# every object depends on a stamp of the compiler, the flags and the -O2 file list: change any of
# them and everything rebuilds (an incremental build over objects made with other flags mixed
# -O2 and -Os code and drew wrongly). The stamp is rewritten only when its text changes.
FLAGS_LINE := $(CC) $(shell $(CC) -dumpversion 2>/dev/null) | $(CFLAGS) | $(LDFLAGS) | -O2: $(notdir $(HOT_OBJS))
$(OUT)/flags.stamp: FORCE
	@mkdir -p $(OUT)
	@echo '$(FLAGS_LINE)' | cmp -s - $@ || echo '$(FLAGS_LINE)' > $@
FORCE:

# -MMD: rebuild objects when a header or .def they include changes (builtins.def!)
$(OUT)/obj/%.o: src/%.c $(OUT)/flags.stamp
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(RT_OBJS:.o=.d) $(TOOL_OBJS:.o=.d)

$(OUT)/libboing.a: $(RT_OBJS)
	@mkdir -p $(dir $@)
	rm -f $@
	$(AR) rcs $@ $^

# standard extensions in the stock interpreter (docs/extensions.md): tools/build-os4.sh STD_EXTS=sqlite
STD_EXTS    ?=
STD_EXT_DIR ?= ext
CXX         ?= ppc-amigaos-g++
ifeq ($(origin CXX),default)
CXX = ppc-amigaos-g++
endif
STDX_SRCS = $(foreach e,$(STD_EXTS),$(firstword $(wildcard $(STD_EXT_DIR)/$(e)/$(e).c $(STD_EXT_DIR)/$(e)/$(e).cpp)))
STDX_OBJS = $(patsubst %,$(OUT)/obj/stdext/%.o,$(notdir $(STDX_SRCS)))
STDX_LIBS = $(if $(strip $(STD_EXTS)),$(shell sh tools/stdext.sh libs os4 $(STD_EXT_DIR) $(STD_EXTS)))
STDX_LD   = $(if $(filter %.cpp,$(STDX_SRCS)),$(CXX) -athread=native,$(CC))
BOING_OBJS = $(if $(strip $(STD_EXTS)),$(filter-out $(OUT)/obj/main/vmext_default.o,$(TOOL_OBJS)) $(OUT)/obj/stdext/glue.o $(STDX_OBJS),$(TOOL_OBJS))

$(OUT)/boing: $(BOING_OBJS) $(OUT)/libboing.a
	$(if $(strip $(STD_EXTS)),$(STDX_LD),$(CC)) $(LDFLAGS) -o $@ $(BOING_OBJS) $(OUT)/libboing.a $(STDX_LIBS) $(LIBS)

$(OUT)/obj/stdext/glue.c: FORCE
	@mkdir -p $(dir $@)
	@sh tools/stdext.sh glue $(STD_EXTS) | cmp -s - $@ || sh tools/stdext.sh glue $(STD_EXTS) > $@
# always: make's 1 s mtimes can miss a glue.c rewritten in the same second as the old glue.o
$(OUT)/obj/stdext/glue.o: $(OUT)/obj/stdext/glue.c FORCE
	$(CC) $(CFLAGS) -c $< -o $@
define stdext_rule
$(OUT)/obj/stdext/$(notdir $(1)).o: $(1) $(OUT)/flags.stamp
	@mkdir -p $(OUT)/obj/stdext
	$(if $(filter %.cpp,$(1)),$(CXX) -athread=native $(filter-out -std=gnu99 -Werror=implicit-function-declaration,$(CFLAGS)),$(CC) $(CFLAGS)) -c $(1) -o $$@
endef
$(foreach s,$(STDX_SRCS),$(eval $(call stdext_rule,$(s))))

# the interpreter as a library for `boing vm` (an interpreter with linked extensions)
$(OUT)/libboingvm.a: $(TOOL_OBJS)
	@mkdir -p $(dir $@)
	rm -f $@
	$(AR) rcs $@ $^

$(OUT)/tests/%: tests/os4/%.c $(OUT)/libboing.a $(OUT)/flags.stamp
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(OUT)/libboing.a $(LIBS)

# no 440-only instructions anywhere
check-cpu: all
	@n=0; for f in $(OUT)/libboing.a $(wildcard $(OUT)/libboingvm.a) $(wildcard $(OUT)/boing) $(TEST_BINS); do \
	  c=$$($(OBJDUMP) -d $$f | grep -c dlmzb); echo "$$f: dlmzb=$$c"; n=$$((n+c)); done; \
	  test $$n -eq 0

clean:
	rm -rf $(OUT)

.PHONY: all check-cpu clean FORCE

# tools run on the guest by the test scripts
$(OUT)/ptr: tools/os4/ptr.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)
all: $(OUT)/ptr
$(OUT)/bbfetch: tools/os4/bbfetch.c
	$(CC) -mcrt=newlib -mcpu=powerpc -O2 -Wall -o $@ $< -lauto
all: $(OUT)/bbfetch
# ready/waiting tasks for os4guest.py's session-start snapshot (infra-m1b)
$(OUT)/tasklist: tools/os4/tasklist.c
	$(CC) -mcrt=newlib -mcpu=powerpc -O2 -Wall -D__USE_INLINE__ -o $@ $< -lauto
all: $(OUT)/tasklist

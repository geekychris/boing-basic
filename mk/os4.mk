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
CFLAGS  ?= -O2
# no -D__USE_INLINE__: the runtime calls IFace->Function() explicitly
CFLAGS  += -mcrt=newlib -mcpu=powerpc -Wall -std=gnu99 -D__USE_OLD_TIMEVAL__ \
           -DBB_PLATFORM_OS4 -Isrc -Isrc/runtime -Isrc/vm -Isrc/compiler
LDFLAGS += -mcrt=newlib -mcpu=powerpc
LIBS    += -lauto -lm

# libboing: the portable runtime plus the OS4 parts
RT_SRCS   := $(wildcard src/runtime/*.c) $(wildcard src/runtime/os4/*.c)
COMP_SRCS := $(wildcard src/compiler/*.c)
VM_SRCS   := $(wildcard src/vm/*.c)
MAIN_SRCS := $(wildcard src/main/*.c)

obj = $(patsubst src/%.c,$(OUT)/obj/%.o,$(1))
RT_OBJS   := $(call obj,$(RT_SRCS))
TOOL_OBJS := $(call obj,$(COMP_SRCS) $(VM_SRCS) $(MAIN_SRCS))

TEST_SRCS := $(wildcard tests/os4/*.c)
TEST_BINS := $(patsubst tests/os4/%.c,$(OUT)/tests/%,$(TEST_SRCS))

all: $(OUT)/libboing.a $(if $(MAIN_SRCS),$(OUT)/boing) $(TEST_BINS)

$(OUT)/obj/%.o: src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/libboing.a: $(RT_OBJS)
	@mkdir -p $(dir $@)
	rm -f $@
	$(AR) rcs $@ $^

$(OUT)/boing: $(TOOL_OBJS) $(OUT)/libboing.a
	$(CC) $(LDFLAGS) -o $@ $(TOOL_OBJS) $(OUT)/libboing.a $(LIBS)

$(OUT)/tests/%: tests/os4/%.c $(OUT)/libboing.a
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(OUT)/libboing.a $(LIBS)

# no 440-only instructions anywhere
check-cpu: all
	@n=0; for f in $(OUT)/libboing.a $(wildcard $(OUT)/boing) $(TEST_BINS); do \
	  c=$$($(OBJDUMP) -d $$f | grep -c dlmzb); echo "$$f: dlmzb=$$c"; n=$$((n+c)); done; \
	  test $$n -eq 0

clean:
	rm -rf $(OUT)

.PHONY: all check-cpu clean

# tools run on the guest by the test scripts
$(OUT)/ptr: tools/os4/ptr.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)
all: $(OUT)/ptr

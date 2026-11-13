# Mesa 7.8.2 OSMesa (classic swrast, fixed-function OpenGL 1.x) as a static library, for the
# OpenGL standard extension (ext/opengl, docs/opengl.md). Driven by build.sh:
#   host:  make TARGET=host            (cc; macOS / Linux)
#   os4:   make TARGET=os4             (inside walkero/amigagccondocker, ppc-amigaos-gcc)
# Output: out/$(TARGET)/libOSMesa.a, out/include/GL/{gl,glext,osmesa}.h

TARGET ?= host
MESA   ?= Mesa-7.8.2
OUT     = out/$(TARGET)
OBJDIR  = obj/$(TARGET)

ifeq ($(TARGET),os4)
CC      = ppc-amigaos-gcc
AR      = ppc-amigaos-ar
RANLIB  = ppc-amigaos-ranlib
# generic -mcpu=powerpc (hard float): 440/440fp code can contain dlmzb, a 440/460-only
# instruction that crashes the X5000, A1222 and G3/G4 (CLAUDE.md of amiga_mcp)
TCFLAGS = -mcrt=newlib -mcpu=powerpc -D__USE_INLINE__
else
CC     ?= cc
AR      = ar
RANLIB  = ranlib
# Mesa 7.8 predates C99-strict compilers: keep old-style declarations warnings, not errors
TCFLAGS = -std=gnu89 -Wno-implicit-function-declaration -Wno-int-conversion \
          -Wno-incompatible-pointer-types -Wno-deprecated-non-prototype -Wno-unknown-warning-option
endif

CFLAGS  = $(TCFLAGS) -O2 -DUSE_EXTERNAL_DXTN_LIB=0 -DNDEBUG -fno-strict-aliasing \
          -w
INCLUDES = -I$(MESA)/include -I$(MESA)/src/mesa -I$(MESA)/src/mesa/main

M = $(MESA)/src/mesa
include $(M)/sources.mak

# everything a classic software driver needs, minus asm helpers and the GLSL compiler (slang),
# which shims/slang_stub.c replaces
SRCS_REL = $(MAIN_SOURCES) $(MATH_SOURCES) $(MATH_XFORM_SOURCES) \
           $(VBO_SOURCES) $(TNL_SOURCES) $(SHADER_SOURCES) \
           $(SWRAST_SOURCES) $(SWRAST_SETUP_SOURCES) \
           $(COMMON_DRIVER_SOURCES) $(GLAPI_SOURCES) \
           drivers/osmesa/osmesa.c

MESA_OBJS = $(addprefix $(OBJDIR)/,$(SRCS_REL:.c=.o))
SHIM_OBJS = $(OBJDIR)/shims/slang_stub.o
LIB = $(OUT)/libOSMesa.a

all: $(LIB) headers

$(OBJDIR)/%.o: $(M)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJDIR)/shims/%.o: shims/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(LIB): $(MESA_OBJS) $(SHIM_OBJS)
	@mkdir -p $(dir $@)
	rm -f $@
	$(AR) rcs $@ $^
	$(RANLIB) $@

headers:
	@mkdir -p out/include/GL
	@cp $(MESA)/include/GL/gl.h $(MESA)/include/GL/glext.h $(MESA)/include/GL/osmesa.h out/include/GL/

clean:
	rm -rf obj out

.PHONY: all headers clean

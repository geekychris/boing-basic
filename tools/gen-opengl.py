#!/usr/bin/env python3
"""gen-opengl.py - writes ext/opengl/opengl_gen.h and ext/opengl/opengl.bbx (docs/opengl.md).

The OpenGL extension's simple functions (numbers in, a GL call, maybe a number out) are listed
here once; this script writes their C wrappers and registration (opengl_gen.h) and the
descriptor (opengl.bbx) with the hand-written functions of opengl.c and the constants of
ext/opengl/GL/gl.h. `tools/gen-opengl.py --check` (make test) fails if the files are stale.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXT = os.path.join(ROOT, "ext", "opengl")

# name, result ('' = Sub, 'Long', 'Double', 'Boolean', 'String'), parameters "name:T ..."
# (T: D = Double, passed to GL as GLfloat or GLdouble; L = Long; B = Boolean), C expression
SIMPLE = [
    # state
    ("glEnable", "", "cap:L", "glEnable((GLenum)cap)"),
    ("glDisable", "", "cap:L", "glDisable((GLenum)cap)"),
    ("glIsEnabled", "Boolean", "cap:L", "glIsEnabled((GLenum)cap)"),
    ("glClearColor", "", "r:D g:D b:D a:D", "glClearColor((GLclampf)r, (GLclampf)g, (GLclampf)b, (GLclampf)a)"),
    ("glClearDepth", "", "depth:D", "glClearDepth(depth)"),
    ("glDepthFunc", "", "func:L", "glDepthFunc((GLenum)func)"),
    ("glDepthMask", "", "flag:B", "glDepthMask(flag ? GL_TRUE : GL_FALSE)"),
    ("glDepthRange", "", "zNear:D zFar:D", "glDepthRange(zNear, zFar)"),
    ("glShadeModel", "", "mode:L", "glShadeModel((GLenum)mode)"),
    ("glCullFace", "", "mode:L", "glCullFace((GLenum)mode)"),
    ("glFrontFace", "", "mode:L", "glFrontFace((GLenum)mode)"),
    ("glPolygonMode", "", "face:L mode:L", "glPolygonMode((GLenum)face, (GLenum)mode)"),
    ("glPolygonOffset", "", "factor:D units:D", "glPolygonOffset((GLfloat)factor, (GLfloat)units)"),
    ("glBlendFunc", "", "sfactor:L dfactor:L", "glBlendFunc((GLenum)sfactor, (GLenum)dfactor)"),
    ("glAlphaFunc", "", "func:L ref:D", "glAlphaFunc((GLenum)func, (GLclampf)ref)"),
    ("glLogicOp", "", "opcode:L", "glLogicOp((GLenum)opcode)"),
    ("glColorMask", "", "r:B g:B b:B a:B", "glColorMask(r != 0, g != 0, b != 0, a != 0)"),
    ("glLineWidth", "", "width:D", "glLineWidth((GLfloat)width)"),
    ("glLineStipple", "", "factor:L pattern:L", "glLineStipple((GLint)factor, (GLushort)pattern)"),
    ("glPointSize", "", "size:D", "glPointSize((GLfloat)size)"),
    ("glHint", "", "target:L mode:L", "glHint((GLenum)target, (GLenum)mode)"),
    ("glScissor", "", "x:L y:L width:L height:L", "glScissor((GLint)x, (GLint)y, (GLsizei)width, (GLsizei)height)"),
    ("glFlush", "", "", "glFlush()"),
    ("glGetError", "Long", "", "glGetError()"),
    ("glClearStencil", "", "s:L", "glClearStencil((GLint)s)"),
    ("glStencilFunc", "", "func:L ref:L mask:L", "glStencilFunc((GLenum)func, (GLint)ref, (GLuint)mask)"),
    ("glStencilOp", "", "fail:L zfail:L zpass:L", "glStencilOp((GLenum)fail, (GLenum)zfail, (GLenum)zpass)"),
    ("glStencilMask", "", "mask:L", "glStencilMask((GLuint)mask)"),
    ("glPushAttrib", "", "mask:L", "glPushAttrib((GLbitfield)mask)"),
    ("glPopAttrib", "", "", "glPopAttrib()"),
    # matrices
    ("glMatrixMode", "", "mode:L", "glMatrixMode((GLenum)mode)"),
    ("glLoadIdentity", "", "", "glLoadIdentity()"),
    ("glPushMatrix", "", "", "glPushMatrix()"),
    ("glPopMatrix", "", "", "glPopMatrix()"),
    ("glTranslatef", "", "x:D y:D z:D", "glTranslatef((GLfloat)x, (GLfloat)y, (GLfloat)z)"),
    ("glRotatef", "", "angle:D x:D y:D z:D", "glRotatef((GLfloat)angle, (GLfloat)x, (GLfloat)y, (GLfloat)z)"),
    ("glScalef", "", "x:D y:D z:D", "glScalef((GLfloat)x, (GLfloat)y, (GLfloat)z)"),
    ("glFrustum", "", "left:D right:D bottom:D top:D zNear:D zFar:D", "glFrustum(left, right, bottom, top, zNear, zFar)"),
    ("glOrtho", "", "left:D right:D bottom:D top:D zNear:D zFar:D", "glOrtho(left, right, bottom, top, zNear, zFar)"),
    ("glViewport", "", "x:L y:L width:L height:L", "glViewport((GLint)x, (GLint)y, (GLsizei)width, (GLsizei)height)"),
    # immediate mode
    ("glBegin", "", "mode:L", "glBegin((GLenum)mode)"),
    ("glEnd", "", "", "glEnd()"),
    ("glVertex2f", "", "x:D y:D", "glVertex2f((GLfloat)x, (GLfloat)y)"),
    ("glVertex3f", "", "x:D y:D z:D", "glVertex3f((GLfloat)x, (GLfloat)y, (GLfloat)z)"),
    ("glVertex4f", "", "x:D y:D z:D w:D", "glVertex4f((GLfloat)x, (GLfloat)y, (GLfloat)z, (GLfloat)w)"),
    ("glColor3f", "", "r:D g:D b:D", "glColor3f((GLfloat)r, (GLfloat)g, (GLfloat)b)"),
    ("glColor4f", "", "r:D g:D b:D a:D", "glColor4f((GLfloat)r, (GLfloat)g, (GLfloat)b, (GLfloat)a)"),
    ("glColor3ub", "", "r:L g:L b:L", "glColor3ub((GLubyte)r, (GLubyte)g, (GLubyte)b)"),
    ("glColor4ub", "", "r:L g:L b:L a:L", "glColor4ub((GLubyte)r, (GLubyte)g, (GLubyte)b, (GLubyte)a)"),
    ("glNormal3f", "", "x:D y:D z:D", "glNormal3f((GLfloat)x, (GLfloat)y, (GLfloat)z)"),
    ("glTexCoord2f", "", "s:D t:D", "glTexCoord2f((GLfloat)s, (GLfloat)t)"),
    ("glRectf", "", "x1:D y1:D x2:D y2:D", "glRectf((GLfloat)x1, (GLfloat)y1, (GLfloat)x2, (GLfloat)y2)"),
    ("glEdgeFlag", "", "flag:B", "glEdgeFlag(flag ? GL_TRUE : GL_FALSE)"),
    # lighting, materials and fog (single values; the 4-value forms are in opengl.c)
    ("glLightf", "", "light:L pname:L param:D", "glLightf((GLenum)light, (GLenum)pname, (GLfloat)param)"),
    ("glLightModelf", "", "pname:L param:D", "glLightModelf((GLenum)pname, (GLfloat)param)"),
    ("glLightModeli", "", "pname:L param:L", "glLightModeli((GLenum)pname, (GLint)param)"),
    ("glMaterialf", "", "face:L pname:L param:D", "glMaterialf((GLenum)face, (GLenum)pname, (GLfloat)param)"),
    ("glColorMaterial", "", "face:L mode:L", "glColorMaterial((GLenum)face, (GLenum)mode)"),
    ("glFogf", "", "pname:L param:D", "glFogf((GLenum)pname, (GLfloat)param)"),
    ("glFogi", "", "pname:L param:L", "glFogi((GLenum)pname, (GLint)param)"),
    # textures
    ("glBindTexture", "", "target:L texture:L", "glBindTexture((GLenum)target, (GLuint)texture)"),
    ("glTexParameteri", "", "target:L pname:L param:L", "glTexParameteri((GLenum)target, (GLenum)pname, (GLint)param)"),
    ("glTexParameterf", "", "target:L pname:L param:D", "glTexParameterf((GLenum)target, (GLenum)pname, (GLfloat)param)"),
    ("glTexEnvi", "", "target:L pname:L param:L", "glTexEnvi((GLenum)target, (GLenum)pname, (GLint)param)"),
    ("glTexEnvf", "", "target:L pname:L param:D", "glTexEnvf((GLenum)target, (GLenum)pname, (GLfloat)param)"),
    ("glTexGeni", "", "coord:L pname:L param:L", "glTexGeni((GLenum)coord, (GLenum)pname, (GLint)param)"),
    ("glIsTexture", "Boolean", "texture:L", "glIsTexture((GLuint)texture)"),
    # display lists
    ("glGenLists", "Long", "range:L", "glGenLists((GLsizei)range)"),
    ("glNewList", "", "list:L mode:L", "glNewList((GLuint)list, (GLenum)mode)"),
    ("glEndList", "", "", "glEndList()"),
    ("glCallList", "", "list:L", "glCallList((GLuint)list)"),
    ("glDeleteLists", "", "list:L range:L", "glDeleteLists((GLuint)list, (GLsizei)range)"),
    ("glIsList", "Boolean", "list:L", "glIsList((GLuint)list)"),
    # vertex arrays (the pointers are set by glVertexPointer & co. in opengl.c)
    ("glEnableClientState", "", "array:L", "glEnableClientState((GLenum)array)"),
    ("glDisableClientState", "", "array:L", "glDisableClientState((GLenum)array)"),
    ("glDrawArrays", "", "mode:L first:L count:L", "bbgl_draw_arrays((GLenum)mode, (GLint)first, (GLsizei)count)"),
    ("glArrayElement", "", "i:L", "glArrayElement((GLint)i)"),
    # queries
    ("glGetInteger", "Long", "pname:L", "bbgl_get_integer((GLenum)pname)"),
    ("glGetFloat", "Double", "pname:L index:L", "bbgl_get_float((GLenum)pname, (int)index)"),
]

# written in opengl.c (only the descriptor lines are generated)
MANUAL = [
    "sub GLAttach(ByVal canvas As Object)",
    "sub GLDetach()",
    "sub GLPresent()",
    "function GLWidth() As Long",
    "function GLHeight() As Long",
    "function GLVersion() As String",
    "sub glClear(ByVal mask As Long)",
    "sub glFinish()",
    "function glGetString(ByVal name As Long) As String",
    "sub glColorRGB(ByVal vbColor As Long)",
    "sub glLight4f(ByVal light As Long, ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glLightfv(ByVal light As Long, ByVal pname As Long, ByVal values As Variant)",
    "sub glMaterial4f(ByVal face As Long, ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glMaterialfv(ByVal face As Long, ByVal pname As Long, ByVal values As Variant)",
    "sub glLightModel4f(ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glFog4f(ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glTexEnv4f(ByVal target As Long, ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glTexGen4f(ByVal coord As Long, ByVal pname As Long, ByVal a As Double, ByVal b As Double, ByVal c As Double, ByVal d As Double)",
    "sub glLoadMatrixf(ByVal m As Variant)",
    "sub glMultMatrixf(ByVal m As Variant)",
    "sub GLGetMatrix(ByVal pname As Long, ByVal m As Variant)",
    "function glGenTexture() As Long",
    "sub glDeleteTexture(ByVal texture As Long)",
    "sub GLTexImage(ByVal width As Long, ByVal height As Long, ByVal pixels As Variant)",
    "sub GLTexImageCanvas(ByVal canvas As Object, ByVal image As Long)",
    "sub glVertexPointer(ByVal size As Long, ByVal values As Variant)",
    "sub glColorPointer(ByVal size As Long, ByVal values As Variant)",
    "sub glNormalPointer(ByVal values As Variant)",
    "sub glTexCoordPointer(ByVal size As Long, ByVal values As Variant)",
    "sub glDrawElements(ByVal mode As Long, ByVal count As Long, ByVal indices As Variant)",
    "sub gluPerspective(ByVal fovy As Double, ByVal aspect As Double, ByVal zNear As Double, ByVal zFar As Double)",
    "sub gluLookAt(ByVal eyeX As Double, ByVal eyeY As Double, ByVal eyeZ As Double, ByVal centerX As Double, ByVal centerY As Double, ByVal centerZ As Double, ByVal upX As Double, ByVal upY As Double, ByVal upZ As Double)",
    "sub gluOrtho2D(ByVal left As Double, ByVal right As Double, ByVal bottom As Double, ByVal top As Double)",
    "function GLProject(ByVal x As Double, ByVal y As Double, ByVal z As Double, ByVal result As Variant) As Boolean",
    "sub glutSolidCube(ByVal size As Double)",
    "sub glutWireCube(ByVal size As Double)",
    "sub glutSolidSphere(ByVal radius As Double, ByVal slices As Long, ByVal stacks As Long)",
    "sub glutWireSphere(ByVal radius As Double, ByVal slices As Long, ByVal stacks As Long)",
    "sub glutSolidTorus(ByVal innerRadius As Double, ByVal outerRadius As Double, ByVal sides As Long, ByVal rings As Long)",
    "sub glutWireTorus(ByVal innerRadius As Double, ByVal outerRadius As Double, ByVal sides As Long, ByVal rings As Long)",
    "sub glutSolidCone(ByVal base As Double, ByVal height As Double, ByVal slices As Long, ByVal stacks As Long)",
    "sub glutWireCone(ByVal base As Double, ByVal height As Double, ByVal slices As Long, ByVal stacks As Long)",
    "sub glutSolidCylinder(ByVal radius As Double, ByVal height As Double, ByVal slices As Long, ByVal stacks As Long)",
    "sub glutSolidCheckerSphere(ByVal radius As Double, ByVal slices As Long, ByVal stacks As Long, ByVal color1 As Long, ByVal color2 As Long)",
]

# constants gl.h lacks (GL 1.4 and extensions that this Mesa implements)
EXTRA_CONSTS = [
    ("GL_GENERATE_MIPMAP", 0x8191),
    ("GL_GENERATE_MIPMAP_HINT", 0x8192),
    ("GL_MIRRORED_REPEAT", 0x8370),
    ("GL_FOG_COORDINATE_SOURCE", 0x8450),
    ("GL_FRAGMENT_DEPTH", 0x8452),
]

TYPES = {"D": ("Double", "double", "bb_arg_double"), "L": ("Long", "long", "bb_arg_long"),
         "B": ("Boolean", "int", "bb_arg_bool")}


def params(spec):
    out = []
    for p in spec.split():
        n, t = p.split(":")
        out.append((n, t))
    return out


def gen_c():
    lines = ["/* opengl_gen.h - GENERATED by tools/gen-opengl.py: do not edit (edit the script) */", ""]
    for name, ret, spec, expr in SIMPLE:
        ps = params(spec)
        lines.append("static bb_value bbgl_f_%s(int argc, bb_value *argv)" % name)
        lines.append("{")
        for i, (n, t) in enumerate(ps):
            lines.append("    %s %s = %s(argv, %d);" % (TYPES[t][1], n, TYPES[t][2], i))
        lines.append("    (void)argc;")
        if not ret:
            lines.append("    %s;" % expr)
            lines.append("    return bb_ret_empty();")
        elif ret == "Long":
            lines.append("    return bb_ret_long((bb_long)(%s));" % expr)
        elif ret == "Double":
            lines.append("    return bb_ret_double((double)(%s));" % expr)
        elif ret == "Boolean":
            lines.append("    return bb_ret_bool((%s) != 0);" % expr)
        else:
            raise SystemExit("bad result type " + ret)
        lines.append("}")
    lines.append("")
    lines.append("static void bbgl_register_generated(void)")
    lines.append("{")
    for name, _, _, _ in SIMPLE:
        lines.append('    bb_register_function("%s", bbgl_f_%s);' % (name, name))
    lines.append("}")
    return "\n".join(lines) + "\n"


def gl_constants():
    seen, out = set(), []
    with open(os.path.join(EXT, "GL", "gl.h")) as f:
        for line in f:
            m = re.match(r"#define\s+(GL_[A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|[0-9]+)\s*$", line.strip())
            if not m or m.group(1) in seen:
                continue
            n = m.group(1)
            if n.startswith("GL_VERSION_") or re.search(r"[a-z]", n):
                continue
            seen.add(n)
            out.append((n, int(m.group(2), 0)))
    for n, v in EXTRA_CONSTS:
        if n not in seen:
            seen.add(n)
            out.append((n, v))
    return out


def gen_bbx():
    out = ["# opengl.bbx - GENERATED by tools/gen-opengl.py: do not edit (edit the script)",
           "# The OpenGL standard extension (opengl.c, docs/opengl.md): Extension=opengl",
           "link OSMesa",
           "# Mesa's span functions keep big stack frames (up to ~100 KB with the 1024 x 1024 cap)",
           "stack 1048576"]
    for name, ret, spec, _ in SIMPLE:
        args = ", ".join("ByVal %s As %s" % (n, TYPES[t][0]) for n, t in params(spec))
        out.append(("function %s(%s) As %s" % (name, args, ret)) if ret else ("sub %s(%s)" % (name, args)))
    out.extend(MANUAL)
    for n, v in gl_constants():
        out.append("const %s = &H%X" % (n, v & 0xFFFFFFFF))
    return "\n".join(out) + "\n"


def main():
    files = {os.path.join(EXT, "opengl_gen.h"): gen_c(), os.path.join(EXT, "opengl.bbx"): gen_bbx()}
    if "--check" in sys.argv:
        bad = [p for p, t in files.items() if not os.path.exists(p) or open(p).read() != t]
        if bad:
            print("gen-opengl: stale, run tools/gen-opengl.py: " + ", ".join(os.path.relpath(p, ROOT) for p in bad))
            return 1
        return 0
    for p, t in files.items():
        with open(p, "w") as f:
            f.write(t)
    return 0


if __name__ == "__main__":
    sys.exit(main())

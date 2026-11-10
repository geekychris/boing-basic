#include <stdint.h>
#include <string.h>
int32_t AddMul(int32_t a, int32_t b, int32_t c) { return (a + b) * c; }
double Hypot2(double x, double y) { return x * x + y * y; }
int32_t StrLenC(const char *s) { return (int32_t)strlen(s); }
const char *Greet(int32_t n) { return n > 0 ? "positive" : "not positive"; }
void Nop(void) {}

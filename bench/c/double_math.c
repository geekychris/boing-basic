#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1, i;
    double x, s = 0, p;
    if (!n) n = 1;
    for (i = 1; i <= 10000000 * n; i++) {
        x = i * 0.000001;
        s += 1 / (x + 1);
        p = ((x * 1.5 - 2.25) * x + 0.75) * x - 0.125;
        s += p * 0.001;
    }
    printf("%.6f\n", s);
    return 0;
}

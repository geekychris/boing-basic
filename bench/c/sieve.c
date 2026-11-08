#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    static char flags[8193];
    long n = argc > 1 ? atol(argv[1]) : 1, r, i, k, count = 0;
    if (!n) n = 1;
    for (r = 1; r <= 1000 * n; r++) {
        count = 0;
        for (i = 2; i <= 8192; i++) flags[i] = 1;
        for (i = 2; i <= 8192; i++)
            if (flags[i]) { for (k = i + i; k <= 8192; k += i) flags[k] = 0; count++; }
    }
    printf(" %ld \n", count);
    return 0;
}

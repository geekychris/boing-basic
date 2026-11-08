#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1, i, s = 0;
    int j, k;
    if (!n) n = 1;
    for (i = 1; i <= 200000 * n; i++)
        for (j = 1; j <= 100; j++) { k = (j * 3 + 7) / 2; s = (s + k % 13 + i) & 0xFFFFF; }
    printf(" %ld \n", s);
    return 0;
}

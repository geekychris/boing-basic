#include <stdio.h>
#include <stdlib.h>
static long fannkuch(long n, long *checksum)
{
    long perm[16], perm1[16], count[16], maxFlips = 0, permCount = 0, r, i, k, t, flips, p0, j;
    for (i = 0; i < n; i++) perm1[i] = i;
    r = n;
    for (;;) {
        while (r != 1) { count[r - 1] = r; r--; }
        for (i = 0; i < n; i++) perm[i] = perm1[i];
        flips = 0;
        while ((k = perm[0]) != 0) {
            for (i = 0, j = k; i < j; i++, j--) { t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
            flips++;
        }
        if (flips > maxFlips) maxFlips = flips;
        *checksum += permCount % 2 == 0 ? flips : -flips;
        for (;;) {
            if (r == n) return maxFlips;
            p0 = perm1[0];
            for (i = 0; i < r; i++) perm1[i] = perm1[i + 1];
            perm1[r] = p0;
            if (--count[r] > 0) break;
            r++;
        }
        permCount++;
    }
}
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1, cs = 0, m;
    if (!n) n = 1;
    m = fannkuch(8 + n, &cs);
    printf(" %ld  %ld \n", cs, m);
    return 0;
}

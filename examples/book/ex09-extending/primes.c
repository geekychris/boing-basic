/* primes.c - step 2: the same sieve in C, called with Declare ... Lib "C" */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int32_t count_primes(int32_t n)
{
    char *composite;
    int32_t i, j, count = 0;
    if (n < 2) return 0;
    composite = calloc((size_t)n + 1, 1);
    if (!composite) return -1;
    for (i = 2; i <= n; i++) {
        if (composite[i]) continue;
        count++;
        for (j = (int32_t)((int64_t)i * i <= n ? i * i : n + 1); j <= n; j += i) composite[j] = 1;
    }
    free(composite);
    return count;
}

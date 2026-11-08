#include <stdio.h>
#include <stdlib.h>
static long fib(long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1;
    if (!n) n = 1;
    printf(" %ld \n", fib(30 + n * 2));
    return 0;
}

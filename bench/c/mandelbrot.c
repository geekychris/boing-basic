#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1, x, y, i, w = 78, h, total = 0;
    char line[80];
    const char *pal = " .:-=+*%";
    if (!n) n = 1;
    h = 400 * n;
    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            double cr = x * 3.0 / w - 2.2, ci = y * 2.4 / h - 1.2, zr = 0, zi = 0, t;
            for (i = 1; i <= 200; i++) {
                t = zr * zr - zi * zi + cr; zi = 2 * zr * zi + ci; zr = t;
                if (zr * zr + zi * zi > 4) break;
            }
            if (i > 200) { line[x] = '#'; total++; } else line[x] = pal[i % 8];
        }
        line[w] = 0;
        if (n == 1 && y % 80 == 0) printf("%s\n", line);
    }
    printf(" %ld \n", total);
    return 0;
}

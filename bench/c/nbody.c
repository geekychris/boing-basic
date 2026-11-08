#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define PI 3.141592653589793
#define SOLAR (4 * PI * PI)
#define DPY 365.24
typedef struct { double x, y, z, vx, vy, vz, m; } body;
static body b[5];
static void init(void)
{
    int i; double px = 0, py = 0, pz = 0;
    b[0].m = SOLAR;
    b[1] = (body){4.84143144246472, -1.16032004402743, -0.103622044471123, 0.00166007664274403 * DPY, 0.00769901118419740 * DPY, -0.0000690460016972063 * DPY, 0.000954791938424327 * SOLAR};
    b[2] = (body){8.34336671824458, 4.1247985641243, -0.403523417114321, -0.00276742510726862 * DPY, 0.00499852801234917 * DPY, 0.0000230417297573763 * DPY, 0.000285885980666130 * SOLAR};
    b[3] = (body){12.8943695621391, -15.1111514016986, -0.223307578892655, 0.00296460137564761 * DPY, 0.00237847173959480 * DPY, -0.0000296589568540237 * DPY, 0.0000436624404335156 * SOLAR};
    b[4] = (body){15.3796971148509, -25.9193146099880, 0.179258772950371, 0.00268067772490389 * DPY, 0.00162824170038242 * DPY, -0.0000951592254519715 * DPY, 0.0000515138902046611 * SOLAR};
    for (i = 0; i < 5; i++) { px += b[i].vx * b[i].m; py += b[i].vy * b[i].m; pz += b[i].vz * b[i].m; }
    b[0].vx = -px / SOLAR; b[0].vy = -py / SOLAR; b[0].vz = -pz / SOLAR;
}
static double energy(void)
{
    int i, j; double e = 0;
    for (i = 0; i < 5; i++) {
        e += 0.5 * b[i].m * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
        for (j = i + 1; j < 5; j++) {
            double dx = b[i].x - b[j].x, dy = b[i].y - b[j].y, dz = b[i].z - b[j].z;
            e -= b[i].m * b[j].m / sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}
static void advance(double dt)
{
    int i, j;
    for (i = 0; i < 5; i++)
        for (j = i + 1; j < 5; j++) {
            double dx = b[i].x - b[j].x, dy = b[i].y - b[j].y, dz = b[i].z - b[j].z;
            double d2 = dx * dx + dy * dy + dz * dz, mag = dt / (d2 * sqrt(d2));
            b[i].vx -= dx * b[j].m * mag; b[i].vy -= dy * b[j].m * mag; b[i].vz -= dz * b[j].m * mag;
            b[j].vx += dx * b[i].m * mag; b[j].vy += dy * b[i].m * mag; b[j].vz += dz * b[i].m * mag;
        }
    for (i = 0; i < 5; i++) { b[i].x += dt * b[i].vx; b[i].y += dt * b[i].vy; b[i].z += dt * b[i].vz; }
}
int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 1, k;
    if (!n) n = 1;
    init();
    printf("%.9f\n", energy());
    for (k = 1; k <= 300000 * n; k++) advance(0.01);
    printf("%.9f\n", energy());
    return 0;
}

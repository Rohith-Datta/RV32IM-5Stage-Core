#include <stdio.h>

int main(void) {
    int a = 0;
    int b = 1;
    int c = 0;
    int i = 0;
    while (i < 5) {
        c = a + b;
        a = b;
        b = c;
        i++;
    }
    return c; // Expected return: 8
}

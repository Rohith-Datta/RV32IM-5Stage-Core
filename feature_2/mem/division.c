int main(void) {
    int a = 100;
    int b = 7;
    int q = a / b;  // 100 / 7 = 14
    int r = a % b;  // 100 % 7 = 2
    int c = q + r;  // 14 + 2 = 16
    return c;       // Expected return: 16 (0x10)
}

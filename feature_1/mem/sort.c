#include <stdio.h>

int main(void) {
    int swapped;
    int n, j;
    n = 3;
    int arr[] = {6, 3, 9};

    do {
        swapped = 0;
        for (j = 0; j < n - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int temp;
                temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
                swapped = 1;
            }
        }
        n = n - 1;
    } while (swapped == 1);

    return arr[0]; // Expected return: 3 (sorted array: {3, 6, 9})
}

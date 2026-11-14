/* memcpy without an ifunc. glibc's RISC-V memcpy is an IFUNC, which the linker reaches through
 * a stub in .iplt. The godot-sandbox addon runs only the .text section, so the first call of
 * that stub faults ("Illegal opcode executed"). Defining memcpy here keeps glibc's out of the
 * link, and with it the IRELATIVE relocation and the stub. */
#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    if ((((uintptr_t)d | (uintptr_t)s) & 7) == 0) {
        for (; n >= 8; n -= 8, d += 8, s += 8) *(uint64_t *)d = *(const uint64_t *)s;
    }
    while (n--) *d++ = *s++;
    return dst;
}

void *__libc_memcpy(void *dst, const void *src, size_t n) __attribute__((alias("memcpy")));

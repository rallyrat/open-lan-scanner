#include "PositiveControl.h"

#include <stdlib.h>
#include <string.h>

/*
 * Disposable ASan positive-control fixture.
 * Lives only in the sanitizer harness target — never linked into the app.
 * Performs an intentional out-of-bounds heap write that AddressSanitizer must catch.
 */
void ols_asan_positive_control(void) {
    char *buf = (char *)malloc(8);
    if (buf == NULL) {
        abort();
    }
    /* Intentional OOB write: one past the allocated region. */
    buf[16] = 'A';
    /* Keep the allocation live so ASan reports the write, not a use-after-free. */
    volatile char sink = buf[0];
    (void)sink;
    free(buf);
}

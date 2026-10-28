#include <sched.h>

#ifdef __cplusplus
extern "C" {
#endif

int pthread_yield(void) {
    return sched_yield();
}

#ifdef __cplusplus
}
#endif

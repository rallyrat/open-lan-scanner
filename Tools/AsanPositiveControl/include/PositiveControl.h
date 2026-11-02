#ifndef OLS_POSITIVE_CONTROL_H
#define OLS_POSITIVE_CONTROL_H

#ifdef __cplusplus
extern "C" {
#endif

/** Intentional heap OOB for verifying AddressSanitizer instrumentation is active. */
void ols_asan_positive_control(void);

#ifdef __cplusplus
}
#endif

#endif /* OLS_POSITIVE_CONTROL_H */

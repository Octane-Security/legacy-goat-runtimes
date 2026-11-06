/* IMS DL/I emulation core: parse an SSA qualification string and look up a segment in a flat
 * hierarchical store. The CBLTDLI entry (COBOL calling convention) wraps these; kept separate so
 * the parse/lookup logic is unit-testable without the COBOL toolchain.
 * Segment layout is legacy-goat/contracts/copybook/customer-segment.cpy (79 bytes). */
#ifndef LG_DLI_H
#define LG_DLI_H

#include <stddef.h>

#define DLI_SEG_LEN 79

/* Max qualification statements in one SSA's boolean qualification (real IMS allows several,
 * connected by boolean operators). */
#define DLI_MAX_QUALS 8

/* One qualification statement: FIELD op VALUE. */
typedef struct {
  char field[24];
  char op[3];
  char value[64];
} dli_qual;

/* One parsed SSA: SEGNAME optionally qualified by (F1 op V1 [<conn> F2 op V2 ...]). Real IMS SSAs
 * support several qualification statements joined by boolean connectors -- AND ('*','&') and
 * OR ('+','|'). This models a single connector kind across the statement list. */
typedef struct {
  char segname[16];
  int qualified;      /* 0 = bare segment name (unqualified GU/GN) */
  int nquals;         /* number of qualification statements (0 when unqualified) */
  dli_qual quals[DLI_MAX_QUALS];
  char connector;     /* '&' = AND (default), '|' = OR */
} dli_ssa;

/* Parse `len` bytes of an SSA into `out`. Returns 0 on success, -1 on malformed input. */
int dli_parse_ssa(const char *ssa, size_t len, dli_ssa *out);

/* Load a store file of newline-separated 79-char records into a malloc'd buffer (`*store`,
 * count*79 bytes, caller frees). Returns record count, or -1 on error. */
int dli_load(const char *path, char **store);

/* Find the first record matching the qualified SSA (equality only). For an unqualified SSA,
 * returns the first record. Returns a pointer into `store` (79 bytes), or NULL if none. */
const char *dli_find(const char *store, int count, const dli_ssa *ssa);

#endif

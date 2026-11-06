/* Unit tests for dli.c. Build: cc -std=c11 -o test_dli test_dli.c dli.c && ./test_dli [seedfile] */
#include "dli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(c)                                                         \
  do {                                                                   \
    if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); ++failures; } \
  } while (0)

static void parse(const char *s, dli_ssa *out) { dli_parse_ssa(s, strlen(s), out); }

int main(int argc, char **argv) {
  const char *seed = argc > 1 ? argv[1] : "seed/customers.dat";
  dli_ssa s;

  /* qualified SSA, no spaces */
  parse("CUSTSEG(CU-CUSTOMER-ID =0000000007)", &s);
  CHECK(strcmp(s.segname, "CUSTSEG") == 0);
  CHECK(s.nquals == 1);
  CHECK(strcmp(s.quals[0].field, "CU-CUSTOMER-ID") == 0);
  CHECK(strchr(s.quals[0].op, '=') != NULL);
  CHECK(strcmp(s.quals[0].value, "0000000007") == 0);
  CHECK(s.qualified == 1);

  /* spaces around field/op/value are tolerated */
  parse("CUSTSEG (CU-CUSTOMER-ID = 0000000008 )", &s);
  CHECK(strcmp(s.quals[0].field, "CU-CUSTOMER-ID") == 0);
  CHECK(strcmp(s.quals[0].value, "0000000008") == 0);

  /* bare segment name -> unqualified */
  parse("CUSTSEG", &s);
  CHECK(s.qualified == 0);

  /* boolean OR qualification (real IMS; also the LG-DLII-001 injection shape) */
  parse("CUSTSEG(CU-CUSTOMER-ID =GHOST|CU-STATUS =ACTIVE)", &s);
  CHECK(s.nquals == 2);
  CHECK(s.connector == '|');
  CHECK(strcmp(s.quals[0].value, "GHOST") == 0);
  CHECK(strcmp(s.quals[1].field, "CU-STATUS") == 0);
  CHECK(strcmp(s.quals[1].value, "ACTIVE") == 0);

  /* load the seed store */
  char *store = NULL;
  int n = dli_load(seed, &store);
  CHECK(n >= 3);
  if (n < 3) { printf("cannot load seed %s\n", seed); return 1; }

  /* qualified find by customer id */
  parse("CUSTSEG(CU-CUSTOMER-ID =0000000008)", &s);
  const char *rec = dli_find(store, n, &s);
  CHECK(rec != NULL);
  if (rec) {
    CHECK(memcmp(rec, "0000000008", 10) == 0);
    CHECK(memcmp(rec + 10, "GLOBEX", 6) == 0);
  }

  /* not found */
  parse("CUSTSEG(CU-CUSTOMER-ID =9999999999)", &s);
  CHECK(dli_find(store, n, &s) == NULL);

  /* qualify on a different field */
  parse("CUSTSEG(CU-STATUS =ACTIVE)", &s);
  CHECK(dli_find(store, n, &s) != NULL);

  /* unqualified GU returns the first record */
  parse("CUSTSEG", &s);
  CHECK(dli_find(store, n, &s) == store);

  /* LG-DLII-001: an OR-injected qualification makes a non-existent customer id match any ACTIVE
     record -- the customer-existence check is bypassed. */
  parse("CUSTSEG(CU-CUSTOMER-ID =9999999999|CU-STATUS =ACTIVE)", &s);
  CHECK(dli_find(store, n, &s) != NULL);

  /* AND of the same statements still requires the (non-existent) id -> no match */
  parse("CUSTSEG(CU-CUSTOMER-ID =9999999999&CU-STATUS =ACTIVE)", &s);
  CHECK(dli_find(store, n, &s) == NULL);

  free(store);
  if (failures == 0) printf("all dli tests passed\n");
  return failures == 0 ? 0 : 1;
}

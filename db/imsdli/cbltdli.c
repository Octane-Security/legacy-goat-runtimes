/* CBLTDLI: the COBOL-callable DL/I entry point. COBOL programs issue
 *   CALL "CBLTDLI" USING dli-func, pcb, io-area, ssa
 * and GnuCOBOL passes each USING item BY REFERENCE (a pointer into COBOL storage). This wraps the
 * unit-tested parse/lookup core in dli.c over the flat hierarchical customer store.
 *
 * Scope: a get-unique (GU/GHU) of the CUSTSEG root segment qualified by an
 * equality SSA. The store is loaded once (lazily) from $CUST_FILE and cached. The 2-byte DL/I status
 * code is written into the PCB at the conventional offset 10 (DBD name 8 + segment level 2):
 * spaces = segment returned, "GE" = not found (or store/parse error). */
#include "dli.h"

#include <stdlib.h>
#include <string.h>

/* Byte offset of the 2-char status code inside the PCB mask (after the 8-char DBD name + 2-char
 * segment-level number). postxfer's CUST-PCB copybook matches this layout. */
#define PCB_STATUS_OFFSET 10

/* The SSA field COBOL passes is fixed-width (postxfer CUST-SSA is PIC X(120)); the parser stops at
 * ')' regardless. Wide enough to carry a boolean qualification (see LG-DLII-001). */
#define SSA_MAX_LEN 120

static char *g_store = NULL;
static int g_count = -1; /* <0 = not loaded yet; >=0 = record count (0 means empty/failed load) */

static void ensure_loaded(void) {
  if (g_count >= 0) return;
  const char *path = getenv("CUST_FILE");
  if (path == NULL || *path == '\0') path = "/var/imsdli/customers.dat";
  g_store = NULL;
  int n = dli_load(path, &g_store);
  g_count = (n < 0) ? 0 : n;
}

static void set_status(char *pcb, const char *code) {
  memcpy(pcb + PCB_STATUS_OFFSET, code, 2);
}

int CBLTDLI(char *func, char *pcb, char *ioarea, char *ssa) {
  (void)func; /* GU/GHU only; treated identically */
  ensure_loaded();

  set_status(pcb, "  ");
  if (g_count <= 0) { set_status(pcb, "GE"); return 0; }

  dli_ssa parsed;
  if (dli_parse_ssa(ssa, SSA_MAX_LEN, &parsed) != 0) { set_status(pcb, "GE"); return 0; }

  const char *rec = dli_find(g_store, g_count, &parsed);
  if (rec == NULL) { set_status(pcb, "GE"); return 0; }

  memcpy(ioarea, rec, DLI_SEG_LEN);
  return 0;
}

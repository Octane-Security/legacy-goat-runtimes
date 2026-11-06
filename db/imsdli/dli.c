#include "dli.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Field map for the CUSTSEG segment (customer-segment.cpy). Offsets/lengths in the 79-byte record. */
static const struct {
  const char *name;
  int off;
  int len;
} CUSTSEG_FIELDS[] = {
    {"CU-CUSTOMER-ID", 0, 10},
    {"CU-STATUS", 50, 8},
    {"CU-RISK-RATING", 58, 1},
};

static int is_op_char(char c) { return c == '=' || c == '<' || c == '>' || c == '!'; }
static int is_conn_char(char c) { return c == '&' || c == '*' || c == '|' || c == '+'; }

int dli_parse_ssa(const char *ssa, size_t len, dli_ssa *out) {
  if (!ssa || !out) return -1;
  memset(out, 0, sizeof(*out));
  out->connector = '&';
  size_t i = 0, n;

  n = 0;
  while (i < len && ssa[i] != '(' && ssa[i] != ' ' && n < sizeof(out->segname) - 1)
    out->segname[n++] = ssa[i++];
  out->segname[n] = '\0';
  if (out->segname[0] == '\0') return -1;

  while (i < len && ssa[i] == ' ') i++;
  if (i >= len || ssa[i] != '(') { out->qualified = 0; return 0; }
  i++;
  out->qualified = 1;

  /* Parse one or more qualification statements (FIELD op VALUE), joined by boolean connectors --
   * AND ('&','*') / OR ('|','+') -- until ')' or end of buffer. This is exactly where an app's
   * unsanitized SSA text is interpreted, so an injected connector + extra statement takes effect
   * (see LG-DLII-001): a single equality qualification can be widened into a boolean one. */
  while (i < len && ssa[i] != ')' && out->nquals < DLI_MAX_QUALS) {
    dli_qual *q = &out->quals[out->nquals];

    while (i < len && ssa[i] == ' ') i++;

    n = 0;
    while (i < len && !is_op_char(ssa[i]) && !is_conn_char(ssa[i]) && ssa[i] != ' ' &&
           ssa[i] != ')' && n < sizeof(q->field) - 1)
      q->field[n++] = ssa[i++];
    q->field[n] = '\0';

    while (i < len && ssa[i] == ' ') i++;
    n = 0;
    while (i < len && is_op_char(ssa[i]) && n < sizeof(q->op) - 1) q->op[n++] = ssa[i++];
    q->op[n] = '\0';

    while (i < len && ssa[i] == ' ') i++;
    n = 0;
    while (i < len && ssa[i] != ')' && !is_conn_char(ssa[i]) && n < sizeof(q->value) - 1)
      q->value[n++] = ssa[i++];
    while (n > 0 && q->value[n - 1] == ' ') n--;
    q->value[n] = '\0';

    if (q->field[0] != '\0') out->nquals++;

    while (i < len && ssa[i] == ' ') i++;
    if (i < len && is_conn_char(ssa[i])) {
      out->connector = (ssa[i] == '|' || ssa[i] == '+') ? '|' : '&';
      i++;
    }
  }
  return 0;
}

int dli_load(const char *path, char **store) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  char line[512];
  int cap = 16, count = 0;
  char *buf = malloc((size_t)cap * DLI_SEG_LEN);
  if (!buf) { fclose(f); return -1; }
  while (fgets(line, sizeof(line), f)) {
    size_t l = strlen(line);
    while (l > 0 && (line[l - 1] == '\n' || line[l - 1] == '\r')) line[--l] = '\0';
    if (l == 0) continue;
    if (l != DLI_SEG_LEN) { free(buf); fclose(f); return -1; }
    if (count == cap) { cap *= 2; buf = realloc(buf, (size_t)cap * DLI_SEG_LEN); if (!buf) { fclose(f); return -1; } }
    memcpy(buf + (size_t)count * DLI_SEG_LEN, line, DLI_SEG_LEN);
    count++;
  }
  fclose(f);
  *store = buf;
  return count;
}

static int field_geom(const char *name, int *off, int *len) {
  for (size_t k = 0; k < sizeof(CUSTSEG_FIELDS) / sizeof(CUSTSEG_FIELDS[0]); k++) {
    if (strcmp(CUSTSEG_FIELDS[k].name, name) == 0) {
      *off = CUSTSEG_FIELDS[k].off;
      *len = CUSTSEG_FIELDS[k].len;
      return 0;
    }
  }
  return -1;
}

/* Trailing-space-insensitive compare of a fixed field against a value. */
static int field_equals(const char *rec, int off, int len, const char *value) {
  int e = len;
  while (e > 0 && rec[off + e - 1] == ' ') e--;
  size_t vl = strlen(value);
  if ((size_t)e != vl) return 0;
  return memcmp(rec + off, value, (size_t)e) == 0;
}

/* Does one record satisfy a single qualification statement? Equality only; any other operator or an
 * unknown field is treated as a non-match (false). */
static int qual_matches(const char *rec, const dli_qual *q) {
  if (strchr(q->op, '<') || strchr(q->op, '>') || strchr(q->op, '!')) return 0;
  int off, len;
  if (field_geom(q->field, &off, &len) != 0) return 0;
  return field_equals(rec, off, len, q->value);
}

const char *dli_find(const char *store, int count, const dli_ssa *ssa) {
  if (!store || !ssa) return NULL;
  if (!ssa->qualified || ssa->nquals == 0) return count > 0 ? store : NULL;
  for (int r = 0; r < count; r++) {
    const char *rec = store + (size_t)r * DLI_SEG_LEN;
    /* Combine the qualification statements with the SSA's boolean connector: OR = any true,
     * AND = all true. */
    int matched = (ssa->connector == '&');
    for (int k = 0; k < ssa->nquals; k++) {
      int m = qual_matches(rec, &ssa->quals[k]);
      if (ssa->connector == '|') matched = matched || m;
      else matched = matched && m;
    }
    if (matched) return rec;
  }
  return NULL;
}

# middleware

The C/C++ layer between REST and the five modules. Non-vulnerable by construction: the benchmark's
injected surface lives only in the language modules, never here.

- `adapters/<lang>/` — one thin adapter per module, translating REST/JSON to the module's native
  calling convention (stdin/stdout + copybook/fixed-record buffers for COBOL/Fortran/SAS; HTTP for
  Pascal and ABAP). All marshalling is length-checked; any DB access the adapter performs is
  parameterized.
- `gateway/` — routes REST between adapters and orchestrates the end-to-end flows.

The adapters must be clean under the same scanners pointed at the corpus, so the benchmark's
positives are unambiguous.

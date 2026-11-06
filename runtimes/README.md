# runtimes

One image per language. Each installs the language toolchain, receives the module source as a
read-only bind mount at `/app-src`, compiles it at container start, and serves the module's REST
contract on `:8080` behind its adapter (`../middleware/adapters/<lang>`).

| Image | Toolchain |
|---|---|
| cobol | GnuCOBOL 3.2 + GixSQL (embedded SQL over the native PGSQL driver) + Berkeley DB 5.3 (indexed files) |
| fortran | gfortran |
| pascal | Free Pascal 3.2.2, headless (fcl-web) |
| sas | shim forwarding PROC SQL pass-through to PostgreSQL |
| abap | open-abap + abaplint transpiler (7.02 subset), swappable for the SAP trial |

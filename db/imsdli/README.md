# imsdli — hierarchical customer store

IMS DL/I emulated: a shim implementing `CALL 'CBLTDLI' USING func,PCB,IO-area,SSA...`
(GU/GN/GHU/ISRT/DLET/REPL) over a hierarchical store. Customer root segment CUSTSEG matches
`legacy-goat/contracts/copybook/customer-segment.cpy`. SSA byte layout:
`SEGNAME` + optional command codes + `(FIELDNAME` + 2-byte operator + value `)` with AND/OR
chaining. Seed segments under `seed/`.

# vsam — indexed account master

The account master (`legacy-goat/contracts/copybook/account-master.cpy`) as a GnuCOBOL
`ORGANIZATION INDEXED` file over Berkeley DB 5.3, keyed on AM-ACCOUNT-ID. Seed records under
`seed/` are loaded into the COBOL container's `/var/vsam` volume at start.

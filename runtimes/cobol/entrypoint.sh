#!/bin/sh
# Compiles the mounted COBOL core + the C++ adapter at start, seeds the VSAM master, then serves.
# App source is bind-mounted at /app-src; the adapter/helpers were COPYed to /build at image build.
set -e

APP=/app; mkdir -p "$APP"
COB=/app-src/cobol
CPY=/app-src/contracts/copybook
GSC=/usr/local/share/gixsql/copy

echo "[cobol] building credential-hash helper"
gcc -shared -fPIC -O2 -o /usr/local/lib/lghash.so /build/lghash.c -lcrypto

echo "[cobol] building DL/I CBLTDLI shim"
gcc -shared -fPIC -O2 -o /usr/local/lib/cbltdli.so \
  /build/imsdli/cbltdli.c /build/imsdli/dli.c -I/build/imsdli
ldconfig

echo "[cobol] seeding DL/I customer store"
mkdir -p /var/imsdli
cp /build/imsdli/seed/customers.dat /var/imsdli/customers.dat

echo "[cobol] compiling COBOL programs"
for p in staffauth postxfer acctstmt cashpost acctmnt; do
  gixpp -e -I"$COB" -I"$CPY" -I"$GSC" -i "$COB/$p.cbl" -o "/tmp/$p.cob"
  cobc -x -o "$APP/$p" "/tmp/$p.cob" -I"$COB" -I"$CPY" -I"$GSC" -L/usr/local/lib -lgixsql
done
# No embedded SQL: VSAM and DL/I only.
cobc -x -o "$APP/acctinq" "$COB/acctinq.cbl" -I"$COB" -I"$CPY"

echo "[cobol] seeding VSAM account master"
cobc -x -o "$APP/loadvsam" /build/loadvsam.cbl -I"$CPY"
mkdir -p /var/vsam
SEED_FILE=/build/seed/accounts.psv ACCT_FILE=/var/vsam/acctmast "$APP/loadvsam"

echo "[cobol] building adapter"
g++ -std=c++17 -O2 -o "$APP/cobol-adapter" /build/adapter/main.cpp \
  -I/build/common -I/build/common/vendor -lpthread

echo "[cobol] starting adapter on :8080"
export LD_LIBRARY_PATH=/usr/local/lib
export COB_LIBRARY_PATH=/usr/local/lib
export COB_PRE_LOAD=libgixsql:lghash:cbltdli
export DATASRC="pgsql://${SQL_HOST:-sqldb}:5432/${SQL_DBNAME:-ledger}?autocommit=off"
export DBUSR="${SQL_USER:-goat}.${SQL_PASSWORD:-labpass}"
export ACCT_FILE=/var/vsam/acctmast
export CUST_FILE=/var/imsdli/customers.dat
exec "$APP/cobol-adapter"

#!/bin/sh
# Compiles the mounted Fortran module + the C++ adapter at start, then serves on :8080.
set -e
APP=/app; mkdir -p "$APP"

echo "[fortran] compiling riskfee"
gfortran -O2 -o "$APP/riskfee" /app-src/fortran/riskfee.f90

echo "[fortran] building adapter"
g++ -std=c++17 -O2 -o "$APP/fortran-adapter" /build/adapter/main.cpp \
  -I/build/common -I/build/common/vendor -lpthread

echo "[fortran] starting adapter on :8080"
exec "$APP/fortran-adapter"

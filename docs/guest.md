# The guest ELF

## Build the guest ELF

```sh
cmake -B build -DCMAKE_TOOLCHAIN_FILE=guest/toolchain.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel -DSTRIPPED=ON -DDOUBLE_PRECISION=ON -S guest
cmake --build build
```

## Stage 1: the C-shim guest

The Lean core is not yet compiled to a RISC-V guest — that needs the Lean runtime
port to `riscv64-linux` (RFD 66606-2153 stage 3). Until it lands, the guest
exports **stub** `character_*` bodies so CI can prove the guest ELF shape
(symbol names present, `.sandbox_variant` correct) without the runtime port. When
stage 3 lands, these stubs become the real Lean-compiled RISC-V functions.

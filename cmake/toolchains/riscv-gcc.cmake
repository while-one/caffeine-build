set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

# Safe cross-compilation: Do not search for host (x86_64) libraries or headers
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Locate toolchain executables dynamically from the system PATH
# Note: For specific RISC-V vendors, this prefix might vary (e.g., riscv32-esp-elf-gcc)
# We default to the standard generic RISC-V GCC toolchain.
find_program(CMAKE_C_COMPILER riscv64-unknown-elf-gcc REQUIRED)
find_program(CMAKE_CXX_COMPILER riscv64-unknown-elf-g++ REQUIRED)
find_program(CMAKE_ASM_COMPILER riscv64-unknown-elf-gcc REQUIRED)

# Locate useful binary utilities for post-build steps
find_program(CMAKE_OBJCOPY riscv64-unknown-elf-objcopy REQUIRED)
find_program(CMAKE_OBJDUMP riscv64-unknown-elf-objdump REQUIRED)
find_program(CMAKE_SIZE riscv64-unknown-elf-size REQUIRED)
find_program(CMAKE_STRIP riscv64-unknown-elf-strip REQUIRED)
find_program(CMAKE_AR riscv64-unknown-elf-ar REQUIRED)
find_program(CMAKE_RANLIB riscv64-unknown-elf-ranlib REQUIRED)

# Bypass compile checks that require a fully linked executable
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

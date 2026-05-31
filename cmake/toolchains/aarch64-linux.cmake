set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CAFFEINE_TOOLCHAIN_PREFIX "aarch64-linux-gnu-" CACHE STRING "Compiler toolchain prefix")

find_program(CMAKE_C_COMPILER ${CAFFEINE_TOOLCHAIN_PREFIX}gcc REQUIRED)
find_program(CMAKE_CXX_COMPILER ${CAFFEINE_TOOLCHAIN_PREFIX}g++ REQUIRED)
find_program(CMAKE_ASM_COMPILER ${CAFFEINE_TOOLCHAIN_PREFIX}gcc REQUIRED)

find_program(CMAKE_OBJCOPY ${CAFFEINE_TOOLCHAIN_PREFIX}objcopy REQUIRED)
find_program(CMAKE_OBJDUMP ${CAFFEINE_TOOLCHAIN_PREFIX}objdump REQUIRED)
find_program(CMAKE_SIZE ${CAFFEINE_TOOLCHAIN_PREFIX}size REQUIRED)
find_program(CMAKE_STRIP ${CAFFEINE_TOOLCHAIN_PREFIX}strip REQUIRED)
find_program(CMAKE_AR ${CAFFEINE_TOOLCHAIN_PREFIX}ar REQUIRED)
find_program(CMAKE_RANLIB ${CAFFEINE_TOOLCHAIN_PREFIX}ranlib REQUIRED)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# --- Clang-Tidy Support ---
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -E -x c -v /dev/null
    ERROR_VARIABLE _COMPILER_OUTPUT
    OUTPUT_QUIET
)
string(REPLACE "\n" ";" _OUTPUT_LINES "${_COMPILER_OUTPUT}")
set(_IS_SEARCH_PATH FALSE)
set(_EXTRA_ARGS "--extra-arg=--target=aarch64-linux-gnu")
foreach(_LINE IN LISTS _OUTPUT_LINES)
    if(_LINE MATCHES "#include <...> search starts here:")
        set(_IS_SEARCH_PATH TRUE)
    elseif(_LINE MATCHES "End of search list.")
        set(_IS_SEARCH_PATH FALSE)
    elseif(_IS_SEARCH_PATH)
        string(STRIP "${_LINE}" _PATH)
        if(EXISTS "${_PATH}")
            list(APPEND _EXTRA_ARGS "--extra-arg=-isystem" "--extra-arg=${_PATH}")
        endif()
    endif()
endforeach()
set(CAFFEINE_CLANG_TIDY_EXTRA_ARGS ${_EXTRA_ARGS} CACHE INTERNAL "Clang-Tidy extra arguments for cross-compilation")

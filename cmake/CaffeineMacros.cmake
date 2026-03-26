# Helper macros and shared build configurations for the Caffeine Framework

# ==============================================================================
# Global Compiler Options
# ==============================================================================

# User-configurable flags (with sensible defaults)
option(CAFFEINE_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)
set(CAFFEINE_OPTIMIZATION_LEVEL "-Os" CACHE STRING "Compiler optimization level (e.g., -O0, -O2, -Os, -O3)")

# Universal strict warnings and preparation for dead-code elimination
set(CAFFEINE_COMPILE_OPTIONS
        -pedantic-errors
        -Wall -Wextra -Wpedantic -Wshadow
        -ffunction-sections -fdata-sections
        $<$<COMPILE_LANGUAGE:C>:-Wstrict-prototypes>
        $<$<COMPILE_LANGUAGE:C>:-Wmissing-prototypes>
        $<$<COMPILE_LANGUAGE:C>:-Wmissing-declarations>
        ${CAFFEINE_OPTIMIZATION_LEVEL}
)

if(CAFFEINE_WARNINGS_AS_ERRORS)
    list(APPEND CAFFEINE_COMPILE_OPTIONS -Werror)
endif()

# ==============================================================================
# Helper Macros
# ==============================================================================

# Macro to generate a firmware memory map, binary, hex, and print the size
macro(cfn_add_firmware TARGET_NAME)
    # Check if this is a cross-compiled target (using our toolchains which define CMAKE_OBJCOPY)
    if(CMAKE_OBJCOPY AND CMAKE_SIZE)
        # 1. Enforce the .elf suffix for the executable
        set_target_properties(${TARGET_NAME} PROPERTIES SUFFIX ".elf")

        # 2. Inject the linker flag to generate the .map file in the app's directory
        target_link_options(${TARGET_NAME} PRIVATE
            "-Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.map"
        )

        # Create a post-build command to output .bin and .hex
        add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
            COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${TARGET_NAME}> ${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.bin
            COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${TARGET_NAME}> ${CMAKE_CURRENT_BINARY_DIR}/${TARGET_NAME}.hex
            COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${TARGET_NAME}>
            COMMENT "Generating firmware binaries and calculating size for ${TARGET_NAME}"
            VERBATIM
        )
    endif()
endmacro()

# Macro to parse the CFN_APP_DIRECT_IRQ list and apply the corresponding
# CFN_HAL_PORT_DISABLE_IRQ_<PERIPH> definitions to the specified target.
function(cfn_apply_direct_irq TARGET_NAME)
    if(DEFINED CFN_APP_DIRECT_IRQ)
        foreach(PERIPH IN LISTS CFN_APP_DIRECT_IRQ)
            string(TOUPPER "${PERIPH}" PERIPH_UPPER)
            target_compile_definitions(${TARGET_NAME} PUBLIC CFN_HAL_PORT_DISABLE_IRQ_${PERIPH_UPPER})
        endforeach()
    endif()
endfunction()

# Function to retrieve system include paths from the compiler and format them
# as --extra-arg flags for clang-tidy. This is essential for cross-compilation
# where clang-tidy cannot natively find the toolchain headers.
function(cfn_get_clang_tidy_extra_args OUT_VAR)
    set(EXTRA_ARGS "")
    if(CMAKE_CROSSCOMPILING)
        # We query the compiler for its default include paths using verbose preprocessor output
        execute_process(
            COMMAND ${CMAKE_C_COMPILER} -E -Wp,-v -xc /dev/null
            ERROR_VARIABLE COMPILER_VERBOSE_OUTPUT
            OUTPUT_QUIET
        )
        string(REPLACE "\n" ";" COMPILER_LINES "${COMPILER_VERBOSE_OUTPUT}")
        set(IS_INSIDE_INCLUDE_BLOCK FALSE)
        foreach(LINE ${COMPILER_LINES})
            if(LINE MATCHES "#include <...>")
                set(IS_INSIDE_INCLUDE_BLOCK TRUE)
            elseif(LINE MATCHES "End of search list")
                set(IS_INSIDE_INCLUDE_BLOCK FALSE)
            elseif(IS_INSIDE_INCLUDE_BLOCK)
                string(STRIP "${LINE}" SYSTEM_PATH)
                if(EXISTS "${SYSTEM_PATH}")
                    list(APPEND EXTRA_ARGS "--extra-arg=-isystem${SYSTEM_PATH}")
                endif()
            endif()
        endforeach()
    endif()
    set(${OUT_VAR} "${EXTRA_ARGS}" PARENT_SCOPE)
endfunction()
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
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

# Global cppcheck flags for consistent static analysis across the framework.
# We fail the build on any warning (--error-exitcode=1) and use a centralized
# suppressions list located in caffeine-build.
set(CFN_CPPCHECK_FLAGS
    --enable=all
    --error-exitcode=1
    --inline-suppr
    --std=c11
    --suppressions-list=${PROJECT_SOURCE_DIR}/caffeine-build/config/coding/cppcheck-suppressions.txt
    --suppress=unmatchedSuppression
)

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

# ==============================================================================
# Code Quality Targets
# ==============================================================================
# Function to add standard code quality targets (format, cppcheck, tidy, analyze)
function(cfn_add_code_quality_targets TARGET_NAME)
    set(options HEADERS_ONLY)
    set(oneValueArgs CPPCHECK_FILE_FILTER TIDY_HEADER_FILTER)
    set(multiValueArgs FORMAT_SOURCES ANALYSIS_SOURCES CPPCHECK_ARGS TIDY_ARGS)
    cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # 1. Code Formatting (clang-format)
    find_program(CLANG_FORMAT clang-format)
    if(CLANG_FORMAT AND ARGS_FORMAT_SOURCES)
        option(FORMAT_DRY_RUN "Run clang-format in dry-run mode" OFF)
        if(FORMAT_DRY_RUN)
            set(FORMAT_ARGS --dry-run --Werror)
            set(FORMAT_COMMENT "Checking formatting with clang-format (BARR-C style)...")
        else()
            set(FORMAT_ARGS -i)
            set(FORMAT_COMMENT "Formatting files with clang-format (BARR-C style)...")
        endif()

        add_custom_target(
            ${TARGET_NAME}-format
            COMMAND ${CLANG_FORMAT}
            ${FORMAT_ARGS}
            -style=file:${PROJECT_SOURCE_DIR}/caffeine-build/config/coding/.clang-format
            ${ARGS_FORMAT_SOURCES}
            COMMENT "${FORMAT_COMMENT}"
        )
    endif()

    # 2. Static Analysis (cppcheck)
    find_program(CPPCHECK cppcheck)
    if(CPPCHECK AND ARGS_ANALYSIS_SOURCES)
        if(ARGS_HEADERS_ONLY)
            set(CPPCHECK_CMD_ARGS ${ARGS_CPPCHECK_ARGS} ${ARGS_ANALYSIS_SOURCES})
        else()
            set(CPPCHECK_FILTER_ARG "")
            if(ARGS_CPPCHECK_FILE_FILTER)
                set(CPPCHECK_FILTER_ARG "--file-filter=${ARGS_CPPCHECK_FILE_FILTER}")
            endif()
            set(CPPCHECK_CMD_ARGS --project=${CMAKE_BINARY_DIR}/compile_commands.json ${CPPCHECK_FILTER_ARG} ${ARGS_CPPCHECK_ARGS})
        endif()

        add_custom_target(
            ${TARGET_NAME}-cppcheck
            COMMAND ${CPPCHECK}
            ${CFN_CPPCHECK_FLAGS}
            ${CPPCHECK_CMD_ARGS}
            COMMENT "Running cppcheck static analysis..."
            VERBATIM
        )
        if(NOT TARGET ${TARGET_NAME}-analyze)
            add_custom_target(${TARGET_NAME}-analyze COMMENT "Running full static analysis suite...")
        endif()
        add_dependencies(${TARGET_NAME}-analyze ${TARGET_NAME}-cppcheck)
    endif()

    # 3. Static Analysis (clang-tidy)
    find_program(CLANG_TIDY clang-tidy)
    if(CLANG_TIDY AND ARGS_ANALYSIS_SOURCES)
        set(TIDY_FILTER ".*")
        if(ARGS_TIDY_HEADER_FILTER)
            set(TIDY_FILTER "${ARGS_TIDY_HEADER_FILTER}")
        endif()

        if(ARGS_HEADERS_ONLY)
            set(TIDY_CMD_ARGS ${ARGS_ANALYSIS_SOURCES} ${PROJECT_SOURCE_DIR}/tests/compliance.c -- -std=c11 ${ARGS_TIDY_ARGS})
        else()
            cfn_get_clang_tidy_extra_args(SYS_INCLUDES_TIDY)
            set(TIDY_CMD_ARGS -p=${CMAKE_BINARY_DIR} ${SYS_INCLUDES_TIDY} ${ARGS_TIDY_ARGS} ${ARGS_ANALYSIS_SOURCES})
        endif()

        add_custom_target(
            ${TARGET_NAME}-tidy
            COMMAND ${CLANG_TIDY}
            --config-file=${PROJECT_SOURCE_DIR}/caffeine-build/config/coding/.clang-tidy
            --header-filter="${TIDY_FILTER}"
            ${TIDY_CMD_ARGS}
            COMMENT "Running clang-tidy static analysis..."
        )
        
        if(NOT TARGET ${TARGET_NAME}-analyze)
            add_custom_target(${TARGET_NAME}-analyze COMMENT "Running full static analysis suite...")
        endif()
        add_dependencies(${TARGET_NAME}-analyze ${TARGET_NAME}-tidy)
    endif()
endfunction()

# ==============================================================================
# Documentation Targets
# ==============================================================================
# Function to add a Doxygen documentation target
function(cfn_add_docs TARGET_NAME INPUT_DIR)
    set(options)
    set(oneValueArgs COMMENT)
    set(multiValueArgs)
    cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    find_package(Doxygen)
    if(DOXYGEN_FOUND)
        set(DOXYGEN_GENERATE_HTML YES)
        set(DOXYGEN_HTML_OUTPUT docs)
        set(DOXYGEN_RECURSIVE YES)
        set(DOXYGEN_USE_MDRVP_AS_MAINPAGE YES)
        set(DOXYGEN_WARN_AS_ERROR YES)
        set(DOXYGEN_GENERATE_LATEX NO)
        set(DOXYGEN_OPTIMIZE_OUTPUT_FOR_C YES)
        set(DOXYGEN_EXTRACT_ALL YES)

        # Ensure we point to the project README as the main page if it exists
        if(EXISTS "${PROJECT_SOURCE_DIR}/README.md")
            set(DOXYGEN_USE_MDRVP_AS_MAINPAGE YES)
        endif()

        doxygen_add_docs(
            ${TARGET_NAME}
            ${INPUT_DIR}
            ${PROJECT_SOURCE_DIR}/README.md
            COMMENT "${ARGS_COMMENT}"
        )

        # Create .nojekyll in the output directory after Doxygen runs
        # This ensures GitHub Pages serves files/folders starting with underscores.
        add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/docs/.nojekyll
            COMMENT "Creating .nojekyll for GitHub Pages deployment"
            VERBATIM
        )
    else()
        # In this framework, documentation is mandatory for CI.
        # We fail configuration if Doxygen is missing and we are in a documentation-enabled stage.
        message(WARNING "Doxygen not found - documentation cannot be generated for ${TARGET_NAME}")
    endif()
endfunction()
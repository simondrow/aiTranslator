cmake_minimum_required(VERSION 3.18)
project(ai_translator_native C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# ============================================================
# 构建选项
# ============================================================
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(AI_BUILD_WHISPER "Build whisper.cpp bridge" ON)
option(AI_BUILD_NLLB "Build NLLB/CTranslate2 bridge" ON)
option(AI_BUILD_FASTTEXT "Build fastText bridge" ON)

# ============================================================
# whisper.cpp 桥接库
# ============================================================
if(AI_BUILD_WHISPER)
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/whisper.cpp/CMakeLists.txt)
        add_subdirectory(third_party/whisper.cpp)
    else()
        message(WARNING "whisper.cpp not found at third_party/whisper.cpp")
    endif()

    add_library(ai_whisper SHARED
        bridge/whisper_bridge.c
    )
    target_include_directories(ai_whisper PRIVATE
        bridge
        third_party/whisper.cpp
    )
    if(TARGET whisper)
        target_link_libraries(ai_whisper PRIVATE whisper)
    endif()
endif()

# ============================================================
# NLLB / CTranslate2 桥接库
# ============================================================
if(AI_BUILD_NLLB)
    add_library(ai_nllb SHARED
        bridge/nllb_bridge.c
    )
    target_include_directories(ai_nllb PRIVATE
        bridge
    )
endif()

# ============================================================
# fastText 桥接库
# ============================================================
if(AI_BUILD_FASTTEXT)
    # fastText 源文件 — 编译为静态库直接链接
    set(FASTTEXT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fastText/src)

    if(EXISTS ${FASTTEXT_SRC_DIR}/fasttext.cc)
        set(FASTTEXT_SOURCES
            ${FASTTEXT_SRC_DIR}/args.cc
            ${FASTTEXT_SRC_DIR}/autotune.cc
            ${FASTTEXT_SRC_DIR}/densematrix.cc
            ${FASTTEXT_SRC_DIR}/dictionary.cc
            ${FASTTEXT_SRC_DIR}/fasttext.cc
            ${FASTTEXT_SRC_DIR}/loss.cc
            ${FASTTEXT_SRC_DIR}/matrix.cc
            ${FASTTEXT_SRC_DIR}/meter.cc
            ${FASTTEXT_SRC_DIR}/model.cc
            ${FASTTEXT_SRC_DIR}/productquantizer.cc
            ${FASTTEXT_SRC_DIR}/quantmatrix.cc
            ${FASTTEXT_SRC_DIR}/utils.cc
            ${FASTTEXT_SRC_DIR}/vector.cc
        )

        add_library(fasttext_core STATIC ${FASTTEXT_SOURCES})
        target_include_directories(fasttext_core PUBLIC ${FASTTEXT_SRC_DIR})
        set_target_properties(fasttext_core PROPERTIES
            POSITION_INDEPENDENT_CODE ON
            CXX_STANDARD 17
        )
        # 移除 -march=native (不适用于交叉编译)
        target_compile_options(fasttext_core PRIVATE -O3 -funroll-loops)

        # 桥接库 (C++ 源文件)
        add_library(ai_fasttext SHARED
            bridge/fasttext_bridge.cpp
        )
        target_include_directories(ai_fasttext PRIVATE
            bridge
            ${FASTTEXT_SRC_DIR}
        )
        target_link_libraries(ai_fasttext PRIVATE fasttext_core)
        target_compile_definitions(ai_fasttext PRIVATE AI_HAS_FASTTEXT)
        set_target_properties(ai_fasttext PROPERTIES
            CXX_STANDARD 17
        )
    else()
        message(WARNING "fastText source not found at ${FASTTEXT_SRC_DIR}")

        # 仅编译 stub 桥接
        add_library(ai_fasttext SHARED
            bridge/fasttext_bridge.cpp
        )
        target_include_directories(ai_fasttext PRIVATE bridge)
    endif()
endif()

# ============================================================
# 安装规则
# ============================================================
install(TARGETS
    $<$<TARGET_EXISTS:ai_whisper>:ai_whisper>
    $<$<TARGET_EXISTS:ai_nllb>:ai_nllb>
    $<$<TARGET_EXISTS:ai_fasttext>:ai_fasttext>
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)

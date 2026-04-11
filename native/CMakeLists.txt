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
    # 添加 whisper.cpp 作为子模块 (需预先 git clone)
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
    # CTranslate2 需要预编译安装或通过 find_package 引入
    # find_package(CTranslate2 REQUIRED)

    add_library(ai_nllb SHARED
        bridge/nllb_bridge.c
    )
    target_include_directories(ai_nllb PRIVATE
        bridge
    )
    # 当 CTranslate2 可用时取消注释:
    # target_link_libraries(ai_nllb PRIVATE CTranslate2::CTranslate2)
endif()

# ============================================================
# fastText 桥接库
# ============================================================
if(AI_BUILD_FASTTEXT)
    # 添加 fastText 作为子模块
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fastText/CMakeLists.txt)
        add_subdirectory(third_party/fastText)
    else()
        message(WARNING "fastText not found at third_party/fastText")
    endif()

    add_library(ai_fasttext SHARED
        bridge/fasttext_bridge.c
    )
    target_include_directories(ai_fasttext PRIVATE
        bridge
        third_party/fastText/src
    )
    if(TARGET fasttext)
        target_link_libraries(ai_fasttext PRIVATE fasttext)
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

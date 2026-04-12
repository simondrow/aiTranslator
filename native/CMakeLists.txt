cmake_minimum_required(VERSION 3.18)
project(ai_translator_native C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# ============================================================
# Build options
# ============================================================
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(AI_BUILD_WHISPER "Build whisper.cpp bridge" ON)
option(AI_BUILD_NLLB "Build NLLB/CTranslate2 bridge" ON)
option(AI_BUILD_FASTTEXT "Build fastText bridge" ON)

# ============================================================
# whisper.cpp bridge
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
# NLLB / CTranslate2 bridge
# ============================================================
if(AI_BUILD_NLLB)
    set(CTRANSLATE2_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/CTranslate2)
    set(SENTENCEPIECE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sentencepiece)

    add_library(ai_nllb SHARED
        bridge/nllb_bridge.cpp
    )
    target_include_directories(ai_nllb PRIVATE bridge)
    set_target_properties(ai_nllb PROPERTIES CXX_STANDARD 17)

    # If CTranslate2 and SentencePiece are built and available
    if(EXISTS ${CTRANSLATE2_DIR}/lib/libctranslate2.a AND
       EXISTS ${SENTENCEPIECE_DIR}/lib/libsentencepiece.a)
        target_include_directories(ai_nllb PRIVATE
            ${CTRANSLATE2_DIR}/include
            ${SENTENCEPIECE_DIR}/include
        )
        target_link_libraries(ai_nllb PRIVATE
            ${CTRANSLATE2_DIR}/lib/libctranslate2.a
            ${SENTENCEPIECE_DIR}/lib/libsentencepiece.a
        )
        target_compile_definitions(ai_nllb PRIVATE AI_HAS_CTRANSLATE2)
        message(STATUS "NLLB: CTranslate2 + SentencePiece found")
    else()
        message(WARNING "CTranslate2/SentencePiece not found, NLLB in stub mode")
    endif()
endif()

# ============================================================
# fastText bridge
# ============================================================
if(AI_BUILD_FASTTEXT)
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
        target_compile_options(fasttext_core PRIVATE -O3 -funroll-loops)

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
        add_library(ai_fasttext SHARED
            bridge/fasttext_bridge.cpp
        )
        target_include_directories(ai_fasttext PRIVATE bridge)
    endif()
endif()

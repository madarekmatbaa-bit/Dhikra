cmake_minimum_required(VERSION 3.10)
project(dhikra_asr LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# whisper.cpp 1.9.5 منسوخ هنا (رخصة MIT)، بالمعالج وحده دون مسرّعات.
set(W ${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp)
file(GLOB GGML_SRC
    ${W}/ggml/src/*.c
    ${W}/ggml/src/*.cpp
    ${W}/ggml/src/ggml-cpu/*.c
    ${W}/ggml/src/ggml-cpu/*.cpp
    ${W}/ggml/src/ggml-cpu/arch/arm/*.c
    ${W}/ggml/src/ggml-cpu/arch/arm/*.cpp
    ${W}/ggml/src/ggml-cpu/arch/x86/*.c
    ${W}/ggml/src/ggml-cpu/arch/x86/*.cpp
    ${W}/ggml/src/ggml-cpu/amx/*.cpp
    ${W}/ggml/src/ggml-cpu/tiled/*.cpp
)
add_library(whisper STATIC ${GGML_SRC} ${W}/src/whisper.cpp ${W}/src/aneforge/whisper-aneforge.cpp)
target_include_directories(whisper PUBLIC ${W}/include ${W}/ggml/include ${W}/ggml/src ${W}/ggml/src/ggml-cpu ${W}/src)
target_compile_definitions(whisper PUBLIC GGML_USE_CPU)
target_compile_definitions(whisper PRIVATE _GNU_SOURCE WHISPER_VERSION="1.9.5")
target_compile_options(whisper PRIVATE -O3 -ffunction-sections -fdata-sections)

find_package(Threads REQUIRED)
add_library(dhikra_asr SHARED dhikra_asr.cpp)
target_compile_options(dhikra_asr PRIVATE -O3 -ffunction-sections -fdata-sections)
target_link_options(dhikra_asr PRIVATE -Wl,--gc-sections)
target_link_libraries(dhikra_asr PRIVATE whisper Threads::Threads)

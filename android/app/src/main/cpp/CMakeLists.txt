cmake_minimum_required(VERSION 3.18)
project(dhikra_asr LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ONNX Runtime (رخصة MIT) يشغّل نموذج التلاوة. تُنزَّل مكتبته الرسمية لأندرويد من Maven Central
# مرة واحدة عند البناء، ويُتحقق من بصمتها. وللبناء على الحاسوب (الاختبارات) يُعطى مسارها:
#   -DORT_INCLUDE=<مجلد الترويسات> -DORT_LIB=<libonnxruntime.so>
set(ORT_VERSION 1.22.0)
set(ORT_SHA256 04a4617a9c797cf49225595e45b5546081cb34c86ac817581141577d3b7dbfe2)

add_library(onnxruntime SHARED IMPORTED)
if(ORT_INCLUDE AND ORT_LIB)
  set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION ${ORT_LIB})
  target_include_directories(onnxruntime INTERFACE ${ORT_INCLUDE})
else()
  set(ORT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/onnxruntime-${ORT_VERSION})
  set(ORT_AAR ${ORT_DIR}/onnxruntime-android.aar)
  if(NOT EXISTS ${ORT_DIR}/headers/onnxruntime_c_api.h)
    file(DOWNLOAD
        https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_VERSION}/onnxruntime-android-${ORT_VERSION}.aar
        ${ORT_AAR}
        EXPECTED_HASH SHA256=${ORT_SHA256}
        TLS_VERIFY ON
        STATUS ORT_STATUS)
    list(GET ORT_STATUS 0 ORT_CODE)
    if(NOT ORT_CODE EQUAL 0)
      file(REMOVE ${ORT_AAR})
      message(FATAL_ERROR "تعذّر تنزيل ONNX Runtime: ${ORT_STATUS}")
    endif()
    file(ARCHIVE_EXTRACT INPUT ${ORT_AAR} DESTINATION ${ORT_DIR} PATTERNS "headers/*" "jni/*")
    file(REMOVE ${ORT_AAR})
  endif()
  set_target_properties(onnxruntime PROPERTIES
      IMPORTED_LOCATION ${ORT_DIR}/jni/${ANDROID_ABI}/libonnxruntime.so)
  target_include_directories(onnxruntime INTERFACE ${ORT_DIR}/headers)
endif()

add_library(dhikra_asr SHARED dhikra_stream.cpp)
target_compile_options(dhikra_asr PRIVATE -O3 -ffunction-sections -fdata-sections)
target_link_options(dhikra_asr PRIVATE -Wl,--gc-sections)
target_link_libraries(dhikra_asr PRIVATE onnxruntime)

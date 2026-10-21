# Linux-native Clang/LLD targeting the Windows LLVM SDK (x64 MSVC ABI).
# WINDOWS_SYSROOT uses xwin's default, case-corrected splat layout.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

foreach(variable LLVM_SDK LLVM_NATIVE_TOOLCHAIN WINDOWS_SYSROOT)
  if(NOT IS_ABSOLUTE "$ENV{${variable}}" OR NOT IS_DIRECTORY "$ENV{${variable}}")
    message(FATAL_ERROR "Export ${variable} as an absolute Linux directory path")
  endif()
endforeach()
set(_llvmkit_native "$ENV{LLVM_NATIVE_TOOLCHAIN}")
set(_llvmkit_sysroot "$ENV{WINDOWS_SYSROOT}")
foreach(tool clang-cl lld-link llvm-lib llvm-rc)
  if(NOT EXISTS "${_llvmkit_native}/bin/${tool}")
    message(FATAL_ERROR "Missing Linux-native tool: ${_llvmkit_native}/bin/${tool}")
  endif()
endforeach()
if(NOT EXISTS "$ENV{LLVM_SDK}/lib/cmake/llvm/LLVMConfig.cmake" OR
   NOT EXISTS "$ENV{LLVM_SDK}/bin/opt.exe")
  message(FATAL_ERROR "LLVM_SDK must point to the extracted Windows LLVM SDK")
endif()
foreach(directory crt/include crt/lib/x86_64 sdk/include/ucrt
    sdk/include/shared sdk/include/um sdk/lib/ucrt/x86_64 sdk/lib/um/x86_64)
  if(NOT IS_DIRECTORY "${_llvmkit_sysroot}/${directory}")
    message(FATAL_ERROR "WINDOWS_SYSROOT needs xwin's default layout: missing ${directory}")
  endif()
endforeach()

set(CMAKE_C_COMPILER "${_llvmkit_native}/bin/clang-cl" CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${_llvmkit_native}/bin/clang-cl" CACHE FILEPATH "")
set(CMAKE_LINKER "${_llvmkit_native}/bin/lld-link" CACHE FILEPATH "")
set(CMAKE_AR "${_llvmkit_native}/bin/llvm-lib" CACHE FILEPATH "")
set(CMAKE_RC_COMPILER "${_llvmkit_native}/bin/llvm-rc" CACHE FILEPATH "")
set(CMAKE_C_COMPILER_TARGET x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

# /X excludes ambient INCLUDE paths; retain Clang's builtin headers explicitly.
execute_process(COMMAND "${_llvmkit_native}/bin/clang-cl" -print-resource-dir
  OUTPUT_VARIABLE _llvmkit_resource_dir OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY)
set(_llvmkit_compile_flags "/X -fms-compatibility-version=19.44")
foreach(directory "${_llvmkit_resource_dir}/include" "${_llvmkit_sysroot}/crt/include"
    "${_llvmkit_sysroot}/sdk/include/ucrt" "${_llvmkit_sysroot}/sdk/include/shared"
    "${_llvmkit_sysroot}/sdk/include/um" "${_llvmkit_sysroot}/sdk/include/winrt")
  if(IS_DIRECTORY "${directory}")
    string(APPEND _llvmkit_compile_flags " -imsvc\"${directory}\"")
  endif()
endforeach()
set(CMAKE_C_FLAGS_INIT "${_llvmkit_compile_flags}")
set(CMAKE_CXX_FLAGS_INIT "${_llvmkit_compile_flags}")

# CMake recognizes this form and skips mt.exe. DLL plugins need no manifest.
set(_llvmkit_link_flags "/manifest:no")
foreach(directory crt/lib/x86_64 sdk/lib/ucrt/x86_64 sdk/lib/um/x86_64)
  string(APPEND _llvmkit_link_flags " -libpath:\"${_llvmkit_sysroot}/${directory}\"")
endforeach()
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_llvmkit_link_flags}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_llvmkit_link_flags}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_llvmkit_link_flags}")

list(PREPEND CMAKE_PREFIX_PATH "$ENV{LLVM_SDK}")
list(PREPEND CMAKE_FIND_ROOT_PATH "$ENV{LLVM_SDK}" "${_llvmkit_sysroot}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

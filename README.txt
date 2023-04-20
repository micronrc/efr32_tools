
A perl script for building cmake files off the SiLabs Gecko SDK and
a shell script for invoking Segger Jlink for uploading firmare.

This repository should be installed as a submodule in the top
directory of your app and mkcmakefiles.pl should be invoked from
the top-level CMakeLists.txt, e.g.

  
  list(APPEND GECKO_COMPONENTS efr32_device efr32_hardware
    iostream sleeptimer emlib)
  execute_process(
    COMMAND perl ${CMAKE_CURRENT_LIST_DIR}/efr32_tools/mkcmakefiles.pl
    ${GECKO_SDK} toolchain CMSIS ${GECKO_COMPONENTS}
    RESULT_VARIABLE ret
  )
  if (NOT ret EQUAL 0)
    message(FATAL_ERROR "mkcmakefiles.pl failed")
  endif()

See repo brd4314a-blinky for an example of use

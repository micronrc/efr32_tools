#!env perl

use strict;
use warnings;
use Time::localtime;
use FileHandle;
use File::Path qw<make_path>;

#
# Create or update all cmake files
#

(my $CmdName = $0) =~ s#.*/##;
my $now = ctime();

my $sdk_dir = shift @ARGV;
die "Usage: $CmdName <SDK dir>\n" unless $sdk_dir;
die "$CmdName: SDK dir '$sdk_dir' does not exist\n" unless -d $sdk_dir;

my @sdk_components = @ARGV;
die "$CmdName: no SDK components specified\n" unless @sdk_components > 0;

my @cmake = (
  { name => 'toolchain', file => 'toolchain.cmake',
    content => q[
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_AR            ##toolpath arm-none-eabi-ar##)
set(CMAKE_ASM_COMPILER  ##toolpath arm-none-eabi-gcc##)
set(CMAKE_C_COMPILER    ##toolpath arm-none-eabi-gcc##)
set(CMAKE_CXX_COMPILER  ##toolpath arm-none-eabi-g++##)
set(CMAKE_LINKER        ##toolpath arm-none-eabi-ld##)
set(CMAKE_OBJCOPY       ##toolpath arm-none-eabi-objcopy##)
set(CMAKE_RANLIB        ##toolpath arm-none-eabi-ranlib##)
set(CMAKE_SIZE          ##toolpath arm-none-eabi-size##)
set(CMAKE_STRIP         ##toolpath arm-none-eabi-strip##)

set(CMAKE_C_FLAGS   "-std=c99 -Wall -Wextra -fdata-sections -ffunction-sections -fomit-frame-pointer -fno-builtin -Wl,--gc-sections ")
set(CMAKE_CXX_FLAGS "\${CMAKE_C_FLAGS} -ffunction-sections -fdata-sections")

set(CMAKE_C_FLAGS_DEBUG     "-O0 -g3 --save-temps")
set(CMAKE_C_FLAGS_RELEASE   "-O2 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG   "\${CMAKE_C_FLAGS_DEBUG}")
set(CMAKE_CXX_FLAGS_RELEASE "\${CMAKE_C_FLAGS_RELEASE}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM   NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY   ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE   ONLY)
  ]},

  { name => 'firmware', file => 'firmware.cmake',
    content => q[
function(create_hex_output TARGET)
  add_custom_target(${TARGET}.hex ALL
    DEPENDS ${TARGET}
    COMMAND ${CMAKE_OBJCOPY} -Oihex ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}
      ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}.hex
  )
endfunction()

function(create_bin_output TARGET)
  add_custom_target(${TARGET}.bin ALL
    DEPENDS ${TARGET}
    COMMAND ${CMAKE_OBJCOPY}
      -Obinary ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}
      ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}.bin
  )
  add_custom_target(flash
    COMMAND pwd && ${CMAKE_CURRENT_LIST_DIR}/../efr32_tools/jflash ${EFR32_DEVICE} ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}.bin
    DEPENDS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}.bin
  )
endfunction()

function(print_sizes TARGET)
  add_custom_command(
    TARGET ${TARGET}
    POST_BUILD
    COMMAND ${CMAKE_SIZE} ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${TARGET}
    COMMENT "Section sizes of the elf file."
  )
endfunction()

  ]},

  { name => 'CMSIS', sdk_subdir => 'platform/CMSIS',
    file => 'gecko_sdk/platform/CMSIS/CMakeLists.txt',
    content => q[
add_library(cmsis INTERFACE)
target_include_directories(cmsis INTERFACE
    ##SDK_SUBDIR##/Include)
    ]
  },

  { name => 'emlib', sdk_subdir => 'platform/emlib',
    file => 'gecko_sdk/platform/emlib/CMakeLists.txt',
    content => q[
add_library(emlib STATIC
  ##eval list_files('*.c', dir => "$sdk_dir/platform/emlib/src",
    prefix => '${GECKO_SDK}/platform/emlib/src/' ) ##
)

target_include_directories(emlib PUBLIC
  ${GECKO_SDK}/platform/emlib/inc)

target_link_libraries(emlib PUBLIC efr32_device)
    ]
  },

  #
  # sleep timer
  #
  { name => 'sleeptimer', sdk_subdir => 'platform/service/sleeptimer',
    file => 'gecko_sdk/platform/sleeptimer/CMakeLists.txt',
    content => q[
add_library(sleeptimer STATIC
  ##eval list_files('*.c', dir => "$sdk_dir/platform/service/sleeptimer/src",
    prefix => '${GECKO_SDK}/platform/service/sleeptimer/src') ##
)
target_include_directories(sleeptimer PUBLIC
  ${GECKO_SDK}/platform/emlib/inc
  ${GECKO_SDK}/platform/common/inc
  ${GECKO_SDK}/platform/peripheral/inc
  ${GECKO_SDK}/platform/service/sleeptimer/inc
  ${GECKO_SDK}/platform/service/sleeptimer/config
)
target_link_libraries(sleeptimer PUBLIC efr32_device)
    ]
  },

  #
  # I/O streams, requires struct to define stream source/sink
  #
  { name => 'iostream',
    sdk_subdir => 'platform/service/iostream',
    file => 'gecko_sdk/platform/iostream/CMakeLists.txt',
    content => q[
add_library(iostream STATIC
  ##SDK_SUBDIR##/src/sl_iostream.c
  ##SDK_SUBDIR##/src/sl_iostream_usart.c
  ##SDK_SUBDIR##/src/sl_iostream_uart.c
  ##SDK_SUBDIR##/src/sl_iostream_stdio.c
  ##SDK_SUBDIR##/src/sl_iostream_retarget_stdio.c
)

#
# Explicity linksl_iostream_retarget_stdio.c.obj to force over-ride
# on the C lib stubs for _write, _read, etc.
#
add_custom_command(TARGET iostream
  POST_BUILD
  COMMAND /bin/echo "Extracting sl_iostream_retarget_stdio.c${CMAKE_C_OUTPUT_EXTENSION}"
    && cd ${CMAKE_BINARY_DIR}/lib
    && ar x libiostream.a sl_iostream_retarget_stdio.c${CMAKE_C_OUTPUT_EXTENSION}
)
target_link_options(iostream
  PUBLIC
  -Wl,../lib/sl_iostream_retarget_stdio.c${CMAKE_C_OUTPUT_EXTENSION}
)

target_include_directories(iostream PUBLIC
  ${GECKO_SDK}/platform/emlib/inc
  ${GECKO_SDK}/platform/common/inc
  ##SDK_SUBDIR##/inc
  ##SDK_DIR##/platform/Device/SiliconLabs/${CPU_FAMILY_U}/Include
)

target_link_libraries(iostream PUBLIC efr32_device)
    ]
  },

  { name => 'efr32_device', sdk_subdir => 'platform/Device',
    file => 'gecko_sdk/platform/Device/CMakeLists.txt',
    content => q[
#
# EFR32 Device Library CMake file
#
# Checks if the device folder is present and adds linker script, system files
# and compiler flags for the device to the build
#
project(efr32_device)

string(TOUPPER ${EFR32_DEVICE} DEVICE_U)
message("Processor: ${DEVICE_U}")

set(DEVICE_FOUND FALSE)
set(TEMP_DEVICE "${DEVICE_U}")

while (NOT DEVICE_FOUND)
  if (EXISTS "##SDK_SUBDIR##/SiliconLabs/${TEMP_DEVICE}")
    set(DEVICE_FOUND TRUE)
  else()
    string(LENGTH ${TEMP_DEVICE} TEMP_DEVICE_LEN)
    math(EXPR TEMP_DEVICE_LEN "${TEMP_DEVICE_LEN}-1")
    string(SUBSTRING ${TEMP_DEVICE} 0 ${TEMP_DEVICE_LEN} TEMP_DEVICE)
  endif()

  if (${TEMP_DEVICE_LEN} EQUAL "0")
    break()
  endif()
endwhile()

if (NOT DEVICE_FOUND)
  message(FATAL_ERROR "failed to find device")
endif()

set(CPU_FAMILY_U ${TEMP_DEVICE})
set(CPU_FAMILY_U ${CPU_FAMILY_U} PARENT_SCOPE ) #<-- set in the parent scope too
string(TOLOWER ${CPU_FAMILY_U} CPU_FAMILY_L)
message("Family: ${CPU_FAMILY_U}")

# TODO: Complete list and check CPUs
if (CPU_FAMILY_U STREQUAL "EFR32BG1B" OR CPU_FAMILY_U STREQUAL "EFR32BG1P"
    OR CPU_FAMILY_U STREQUAL "EFR32BG1V" OR CPU_FAMILY_U STREQUAL "EFR32BG12P"
    OR CPU_FAMILY_U STREQUAL "EFR32BG13P" OR CPU_FAMILY_U STREQUAL "EFR32BG21"
    OR CPU_FAMILY_U STREQUAL "EFR32BG122" OR CPU_FAMILY_U STREQUAL "EFR32FG1P"
    OR CPU_FAMILY_U STREQUAL "EFR32FG1V" OR CPU_FAMILY_U STREQUAL "EFR32FG12P"
    OR CPU_FAMILY_U STREQUAL "EFR32FG1V" OR CPU_FAMILY_U STREQUAL "EFR32FG12P"
    OR CPU_FAMILY_U STREQUAL "EFR32FG13P" OR CPU_FAMILY_U STREQUAL "EFR32FG14P"
    OR CPU_FAMILY_U STREQUAL "EFR32FG14V" OR CPU_FAMILY_U STREQUAL "EFR32FG22"
    OR CPU_FAMILY_U STREQUAL "EFR32FG23" OR CPU_FAMILY_U STREQUAL "EFR32MG1B"
    OR CPU_FAMILY_U STREQUAL "EFR32MG1P" OR CPU_FAMILY_U STREQUAL "EFR32MG1V"
    OR CPU_FAMILY_U STREQUAL "EFR32MG12P" OR CPU_FAMILY_U STREQUAL "EFR32MG13P"
    OR CPU_FAMILY_U STREQUAL "EFR32MG14P" OR CPU_FAMILY_U STREQUAL "EFR32FG22")
  message("Architecture: cortex-m4")
  set(CPU_TYPE "m4")
  set(CPU_FIX -mfpu=fpv4-sp-d16
              -mfloat-abi=softfp)

elseif (CPU_FAMILY_U STREQUAL "EFR32MG21" OR CPU_FAMILY_U STREQUAL "EFR32BG21"
    OR CPU_FAMILY_U STREQUAL "EFR32MG22" OR CPU_FAMILY_U STREQUAL "EFR32BG22"
    OR CPU_FAMILY_U STREQUAL "BGM22")
  message("Architecture: cortex-m33")
  set(CPU_TYPE "m33")
  set(CPU_FIX -march=armv8-m.main+dsp
              -mcmse
              -mfpu=fpv5-sp-d16
              -mfloat-abi=hard
              -falign-functions=2)
else ()
  message("Architecture: cortex-m3 (default)")
  set(CPU_TYPE "m3")
  set(CPU_FIX -mfix-cortex-m3-ldrd)
endif()

add_library(${PROJECT_NAME} STATIC
  ##SDK_SUBDIR##/SiliconLabs/${CPU_FAMILY_U}/Source/GCC/startup_${CPU_FAMILY_L}.c
  ##SDK_SUBDIR##/SiliconLabs/${CPU_FAMILY_U}/Source/system_${CPU_FAMILY_L}.c)

target_include_directories(${PROJECT_NAME}
  PUBLIC
  ##SDK_SUBDIR##/SiliconLabs/${CPU_FAMILY_U}/Include
)

# Set linker definitions
set(EFR32_LINKER_FILE
  ##SDK_SUBDIR##/SiliconLabs/${CPU_FAMILY_U}/Source/GCC/${CPU_FAMILY_L}.ld
)

# C Flags
set(EFR32_DEVICE_C_FLAGS
  -mthumb
  -mcpu=cortex-${CPU_TYPE}
  -D${EFR32_DEVICE}
  ${CPU_FIX}
)

set(EFR32_DEVICE_C_LFLAGS
  ${EFR32_DEVICE_C_FLAGS}
  -Wl,-Map=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_PROJECT_NAME}.map
  -Wl,-T${EFR32_LINKER_FILE}
)

# C++ Flags
set(EFR32_DEVICE_CXX_FLAGS
  ${EFR32_DEVICE_C_FLAGS}
  -fno-exceptions
  -fno-rtti
)

set(EFR32_DEVICE_CXX_LFLAGS
  ${EFR32_DEVICE_CXX_FLAGS}
  -Wl,-Map=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_PROJECT_NAME}.map
  -Wl,-T${EFR32_LINKER_FILE}
)

# Assembler Flags
set(EFR32_ASM_FLAGS
  ${EFR32_C_FLAGS}
  -x assembler-with-cpp
)

target_compile_options(${PROJECT_NAME}
  PUBLIC
  $<$<COMPILE_LANGUAGE:ASM>:${EFR32_ASM_FLAGS}>
  $<$<COMPILE_LANGUAGE:C>:${EFR32_DEVICE_C_FLAGS}>
  $<$<COMPILE_LANGUAGE:CXX>:${EFR32_DEVICE_CXX_FLAGS}>
)

target_link_options(${PROJECT_NAME}
  PUBLIC
  $<$<COMPILE_LANGUAGE:C>:${EFR32_DEVICE_C_LFLAGS}>
  $<$<COMPILE_LANGUAGE:CXX>:${EFR32_DEVICE_CXX_LFLAGS}>
)

target_link_libraries(${PROJECT_NAME} cmsis)
    ]
  },

#
# Needs work to add other protocols - e.g. flex
#
  { name => 'protocol', sdk_subdir => 'protocol',
    file => 'gecko_sdk/protocol/CMakeLists.txt',
    content => q[
project(efr32_protocol)

add_library(${PROJECT_NAME} INTERFACE)

target_include_directories(${PROJECT_NAME} INTERFACE
  ##SDK_SUBDIR##/bluetooth/inc
  ##SDK_SUBDIR##/bluetooth/config
)

target_link_options(${PROJECT_NAME} INTERFACE
  -L##SDK_SUBDIR##/bluetooth/lib/${CPU_FAMILY_U}/GCC)

add_library(bluetooth STATIC IMPORTED)
set_target_properties(bluetooth PROPERTIES IMPORTED_LOCATION
  ##SDK_SUBDIR##/bluetooth/lib/${CPU_FAMILY_U}/GCC/libbluetooth.a)

target_link_libraries(${PROJECT_NAME} INTERFACE bluetooth)

if (BL_MESH)
  add_library(bluetooth_mesh STATIC IMPORTED)
  set_target_properties(bluetooth_mesh PROPERTIES IMPORTED_LOCATION
    ##SDK_SUBDIR##/bluetooth/lib/${CPU_FAMILY_U}/GCC/libbluetooth_mesh.a)
  target_link_libraries(${PROJECT_NAME} INTERFACE bluetooth_mesh)
endif()

if (BL_PSSTORE)
  add_library(psstore STATIC IMPORTED)
  set_target_properties(psstore PROPERTIES IMPORTED_LOCATION
    ##SDK_SUBDIR##/bluetooth/lib/${CPU_FAMILY_U}/GCC/libpsstore.a)
  target_link_libraries(${PROJECT_NAME} INTERFACE psstore)
endif()
    ]
  },

  { name => 'efr32_hardware', sdk_subdir => 'hardware',
    file => 'gecko_sdk/hardware/CMakeLists.txt',
    content => q[
project(efr32_hardware)

add_library(${PROJECT_NAME} INTERFACE)

#target_include_directories(${PROJECT_NAME} PUBLIC
#  ##SDK_SUBDIR##/kit/common/drivers
#)

target_include_directories(${PROJECT_NAME} INTERFACE
  ##SDK_SUBDIR##/kit/${CPU_FAMILY_U}_${BOARD}/config
  ##SDK_SUBDIR##/kit/common/bsp
  ##SDK_SUBDIR##/kit/common/bsp/thunderboard
  ##SDK_SUBDIR##/kit/common/drivers
  ##SDK_SUBDIR##/kit/common/halconfig
  ##SDK_SUBDIR##/module/config
  ##SDK_DIR##/platform/CMSIS/Include
  ##SDK_DIR##/platform/emlib/inc
  ##SDK_DIR##/platform/Device/SiliconLabs/${CPU_FAMILY_U}/Include
)

#target_compile_options(${PROJECT_NAME}
#  PUBLIC
#  -D${EFR32_DEVICE}
#)

    ],
  },

);

my %cmake = ();
foreach (@cmake) {
  $cmake{$_->{name}} = $_;
}

my @subdirs = ();
foreach (@sdk_components) {
  my $cmpnt = $cmake{$_};
  die "$CmdName: no specification for component '$_'\n" unless $cmpnt;

  if ($cmpnt->{sdk_subdir}) {
    my $file = $cmpnt->{file};
    die "$CmdName: component '", $cmpnt->{name}, "' has file '$file' that does not end with '/CMakeLists.txt'\n" unless $file =~ m#/CMakeLists.txt$#;
    $file =~ s#^[^/]+/##;
    $file =~ s#/CMakeLists.txt$##;
    push @subdirs, $file;
  }

  mk_cmakefile($cmpnt);
}

#
# Create top-level cmake files
#
my $fh = create_file('gecko_sdk/CMakeLists.txt');
foreach (@subdirs) {
  print $fh "add_subdirectory($_)\n";
}
$fh->close;

exit 0;

##################################################################3

sub mk_cmakefile
{
  my ($cmake_data) = @_;
  my $name = $cmake_data->{name};

  my $file = $cmake_data->{file};
  printf "Create $file...\n";
  my $fh = create_file($file);

  my $cmake = $cmake_data->{content};

  while ($cmake =~ /(##([^#][^#]+)##)/s) {
    my ($orig, $expr) = (quotemeta($1), $2);

    $expr =~ /\s*(\w+)(\s+(.+))?\s*/s;
    my ($keyword, $arg) = ($1, $3);
    my $repl;
    if ($keyword eq 'toolpath') {
      $repl = '${ARM_TOOLCHAIN}/bin/' . $arg . '${CMAKE_EXECUTABLE_SUFFIX}';
    }
    elsif ($keyword eq 'eval') {
#print STDERR "eval '$arg'\n";
      $repl = eval $arg;
      die "$CmdName: mk_cmakefile($name) eval failed = $@\n" if $@;
    }
    elsif ($keyword eq 'SDK_DIR') {
      $repl = $sdk_dir;
    }
    elsif ($keyword eq 'SDK_SUBDIR') {
      $repl = $cmake_data->{sdk_subdir}
        or die "$CmdName: mk_cmakefile($name) no 'sdk_subdir' param\n";
      $repl = "$sdk_dir/$repl";
    }
    else {
      die "$CmdName: mk_cmakefile($name) unexpected ## key '$keyword' in expr '$expr'\n";
    }
    $cmake =~ s/$orig/$repl/m;
  }
  print $fh $cmake;
  $fh->close;
}


sub create_file
{
  my ($fname) = @_;

#print "create_file($fname)\n";
  if ($fname =~ m#(.+)/.+$#) {
    create_dir($1);
  }

  my $fh = FileHandle->new($fname, 'w');
  die "$CmdName: failed to create $fname - $!\n" unless $fh;

  print $fh <<EoF;
#
# DO NOT EDIT THIS FILE
#
# Created by $CmdName on $now
#

EoF

  return $fh;
}

sub create_dir
{
  my ($dpath) = @_;

  unless (-d $dpath) {
#print "create_dir($dpath)\n";
    make_path($dpath);
    die "$CmdName: failed to create dir '$dpath' - $!\n" unless -d $dpath;
  }
}

sub list_files
{
  my ($glob, %opt) = @_;

  my $prefix = $opt{prefix} || '';
  my $dir = '.';
  if ($opt{dir}) {
    $dir = $opt{dir};
  }

  my $files = `chdir $dir; ls $glob`;
  die "$CmdName: list_files($dir) no files found\n" unless $files =~ /\S/;

  $prefix .= '/' unless $prefix =~ m#/$#;

  my @files = map { "${prefix}$_" } grep { $_ } split /[\s\n\r]+/, $files;
  
  if (wantarray) {
    return @files;
  }
  return join("\n", @files);
}

# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.20)
project(presentation_hub LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 REQUIRED COMPONENTS Core Network)
add_executable(presentation-hub-core core/main.cpp)
target_link_libraries(presentation-hub-core PRIVATE Qt6::Core Qt6::Network)
set_target_properties(presentation-hub-core PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/presentation-hub/bin"
)
install(TARGETS presentation-hub-core RUNTIME DESTINATION bin)
include(CTest)
if(BUILD_TESTING)
  add_executable(presentation-rules-test tests/presentation_rules.cpp)
  target_include_directories(presentation-rules-test PRIVATE core)
  target_link_libraries(presentation-rules-test PRIVATE Qt6::Core)
  add_test(NAME presentation-rules COMMAND presentation-rules-test)
endif()

# Based on c_src.mk from erlang.mk by Loic Hoguin <essen@ninenines.eu>

CURDIR := $(shell pwd)
BASEDIR := $(abspath $(CURDIR)/..)

PROJECT := prometheus_process_collector

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts/erts-~ts/include/\", [code:root_dir(), erlang:system_info(version)]), erlang:halt().")
ERL_INTERFACE_INCLUDE_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, include)]), erlang:halt().")
ERL_INTERFACE_LIB_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, lib)]), erlang:halt().")

C_SRC_DIR = $(CURDIR)
C_SRC_OUTPUT ?= $(CURDIR)/../priv/$(PROJECT).so
MEMTEST_OUTPUT ?= $(CURDIR)/../_build/memory_test

.PHONY: memory-test clean

# System type, sources, compiler, and link command.

UNAME_SYS := $(shell uname -s)
ifeq ($(UNAME_SYS), Linux)
	CC ?= cc
	CFLAGS += -O3 -finline-functions -std=c11 -Wall -fPIC \
		  -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)
	LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei
	SOURCES = prometheus_process_collector_nif_linux.c
	LINKER = $(CC)
else ifeq ($(UNAME_SYS), Darwin)
	CXX ?= c++
	CXXFLAGS += -O3 -finline-functions -fPIC -std=c++11 -Wall \
		    -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)
	LDFLAGS += -undefined dynamic_lookup
	LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei -lstdc++
	SOURCES = prometheus_process_collector_nif.cc prometheus_process_info_macos.cc
	PSOURCES = prometheus_process_info_macos.cc
	LINKER = $(CXX)
else ifeq ($(UNAME_SYS), FreeBSD)
	CXX ?= c++
	CXXEFLAGS += -D__STANDALONE_TEST__ -std=c++11 -Wall
	CXXFLAGS += -O3 -finline-functions -fPIC -std=c++11 -Wall \
		    -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)
	LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei -lstdc++
	SOURCES = prometheus_process_collector_nif.cc prometheus_process_info_freebsd.cc
	PSOURCES = prometheus_process_info_freebsd.cc
	LINKER = $(CXX)
endif

LDFLAGS += -shared

# Verbosity.

cc_verbose_0  = @echo " CC    " $(?F);
cc_verbose    = $(cc_verbose_$(V))
cpp_verbose_0 = @echo " CPP   " $(?F);
cpp_verbose   = $(cpp_verbose_$(V))
link_verbose_0 = @echo " LD    " $(@F);
link_verbose   = $(link_verbose_$(V))

OBJECTS = $(addsuffix .o, $(basename $(SOURCES)))

$(C_SRC_OUTPUT): $(OBJECTS)
	@mkdir -p $(BASEDIR)/priv/
	$(link_verbose) $(LINKER) $(OBJECTS) $(LDFLAGS) $(LDLIBS) -o $(C_SRC_OUTPUT)

%.o: %.c
	$(cc_verbose) $(CC) $(CFLAGS) $(CPPFLAGS) -c $(OUTPUT_OPTION) $<

%.o: %.cc
	$(cpp_verbose) $(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $(OUTPUT_OPTION) $<

memory-test:
ifeq ($(UNAME_SYS), Linux)
	@echo "memory-test target is not applicable on Linux (no C++ NIF code on this platform)"
else
	@mkdir -p $(BASEDIR)/_build/
	$(CXX) $(CXXEFLAGS) $(LDLIBS) prometheus_process_info_mt.cc $(PSOURCES) -o $(MEMTEST_OUTPUT)
	valgrind --leak-check=full --error-exitcode=1 $(MEMTEST_OUTPUT) 2
endif

clean:
	@rm -f $(C_SRC_OUTPUT) $(OBJECTS)

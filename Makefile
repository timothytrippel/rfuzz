
FIR := Sodor3Stage.fir
DUT := Sodor3Stage

ROOT := $(shell pwd)
BUILD := $(ROOT)/build
INPUT := $(ROOT)/benchmarks/$(FIR)
ANNO_FILE := $(ROOT)/benchmarks/$(DUT).anno.json
INSTRUMENTED_V := $(BUILD)/$(DUT).v
INSTRUMENTED_FIR := $(BUILD)/$(DUT).lo.fir
INSTRUMENTATION_TOML := $(BUILD)/$(DUT)_InstrumentationInfo.toml
TOML := $(BUILD)/$(DUT).toml
E2ECOV_TOML := $(BUILD)/$(DUT).e2e.toml
VERILATOR_HARNESS := $(BUILD)/$(DUT)_VHarness.v
FUZZ_SERVER := $(BUILD)/$(DUT)_server
E2ECOV_HARNESS := $(BUILD)/$(DUT)_E2EHarness.v
E2ECOV := $(BUILD)/$(DUT)_cov

SBT := sbt



default: $(VERILATOR_HARNESS)

################################################################################
# gobal clean
################################################################################
clean:
	rm -rf build/*
	rm -rf harness/*.anno
	rm -rf harness/*.fir
	rm -rf harness/*.v
	rm -rf harness/*.f
	rm -rf harness/test_run_dir

################################################################################
# instrumentation rules
################################################################################
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
COMMA := ,
FIRRTL_TRANSFORMS := \
	rfuzz.NoDedupTransform \
	rfuzz.ReplaceMemsTransform \
	rfuzz.SplitMuxConditions \
	rfuzz.ProfilingTransform \
	firrtl.passes.wiring.WiringTransform \
	rfuzz.AddMetaResetTransform
INSTRUMENTATION_SOURCES := $(shell find instrumentation -name '*.scala')


ifeq ($(wildcard $(ANNO_FILE)),)
  ANNO_CMD =
else
  ANNO_CMD = -faf $(ANNO_FILE)
endif

lookup_scala_srcs = $(shell find $(1)/ -iname "*.scala" 2> /dev/null)


$(INSTRUMENTED_V) $(INSTRUMENTED_FIR) $(INSTRUMENTATION_TOML): $(INPUT) $(INSTRUMENTATION_SOURCES)
	cd instrumentation ;\
	$(SBT) "runMain firrtl.stage.FirrtlMain -i $< -o $(DUT) -X verilog -E low -E verilog -ll info -fct $(subst $(SPACE),$(COMMA),$(FIRRTL_TRANSFORMS)) $(ANNO_CMD)"
	mkdir -p $(BUILD)
	mv instrumentation/$(DUT).toml $(INSTRUMENTATION_TOML)
	mv instrumentation/$(DUT).lo.fir $(INSTRUMENTED_FIR)
	mv instrumentation/$(DUT).v $(INSTRUMENTED_V)

instrumentation: $(INSTRUMENTED_V) $(INSTRUMENTED_FIR) $(INSTRUMENTATION_TOML)

################################################################################
# harness rules
################################################################################
HARNESS_SRC := $(shell find harness/src -name '*.scala')
HARNESS_TEST := $(shell find harness/test -name '*.scala')

$(VERILATOR_HARNESS) $(TOML) $(E2ECOV_HARNESS) $(E2ECOV_TOML): $(INSTRUMENTATION_TOML) $(HARNESS_SRC)
	cd harness ;\
	sbt "run $(INSTRUMENTATION_TOML) $(TOML) $(E2ECOV_TOML)"
	mv harness/VerilatorHarness.v $(VERILATOR_HARNESS)
	mv harness/E2ECoverageHarness.v $(E2ECOV_HARNESS)


################################################################################
# Verilator Binary Rules
################################################################################
VERILATOR_TB_SRC = $(shell ls verilator/*.hpp verilator/*.cpp verilator/*.h verilator/*.c verilator/meson.build)
VERILATOR_BUILD = $(BUILD)/v$(DUT)


$(FUZZ_SERVER): $(TOML) $(VERILATOR_HARNESS) $(INSTRUMENTED_V) $(VERILATOR_TB_SRC)
	mkdir -p $(VERILATOR_BUILD)
	cd $(VERILATOR_BUILD) && meson ../../verilator --buildtype=release \
	                         -Dtrace=false -Dbuild_dir='$(BUILD)' -Ddut='$(DUT)' \
	                      && ninja
	mv $(VERILATOR_BUILD)/server $(FUZZ_SERVER)

################################################################################
# Verilator end-to-end coverage Binary Rules
################################################################################
VERILATOR_E2E_SRC = $(shell ls e2e/*.cpp e2e/meson*)
VERILATOR_E2E_BUILD = $(BUILD)/v$(DUT).e2e


$(E2ECOV): $(TOML) $(VERILATOR_HARNESS) $(INSTRUMENTED_V) $(VERILATOR_E2E_SRC)
	mkdir -p $(VERILATOR_E2E_BUILD)
	cd $(VERILATOR_E2E_BUILD) && meson ../../e2e --buildtype=release \
	                             -Dtrace=false -Dbuild_dir='$(BUILD)' -Ddut='$(DUT)' \
	                          && ninja
	mv $(VERILATOR_E2E_BUILD)/cov $(E2ECOV)


################################################################################
# Build All Pseudo Target
################################################################################
bin: $(FUZZ_SERVER) $(E2ECOV)
	echo "done"


################################################################################
# Fuzz Server Pseudo Target
################################################################################
run: $(FUZZ_SERVER) $(E2ECOV)
	rm -rf /tmp/fpga
	mkdir /tmp/fpga
	$(FUZZ_SERVER)

################################################################################
# Docker Environment Target
################################################################################
build-env:
	docker build --no-cache -t rfuzz/env .

env:
	docker run -it --rm \
		-v $(shell pwd)/analysis:/src/rfuzz/analysis \
		-v $(shell pwd)/benchmarks:/src/rfuzz/benchmarks \
		-v $(shell pwd)/doc:/src/rfuzz/doc \
		-v $(shell pwd)/e2e:/src/rfuzz/e2e \
		-v $(shell pwd)/fpga:/src/rfuzz/fpga \
		-v $(shell pwd)/fuzzer:/src/rfuzz/fuzzer \
		-v $(shell pwd)/harness:/src/rfuzz/harness \
		-v $(shell pwd)/instrumentation:/src/rfuzz/instrumentation \
		-v $(shell pwd)/midas:/src/rfuzz/midas \
		-v $(shell pwd)/results:/src/rfuzz/results \
		-v $(shell pwd)/verilator:/src/rfuzz/verilator \
		-v $(shell pwd)/Makefile:/src/rfuzz/Makefile \
		-v $(shell pwd)/run.sh:/src/rfuzz/run.sh \
		-t rfuzz/env /bin/bash

.PHONY: build-env env instrumentation run

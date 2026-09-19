# In-process logos-delivery simulator.
#
# Requires LD_ROOT pointing at a logos-delivery checkout that has been built
# once (it needs nimble.paths):
#
#   make LD_ROOT=~/src/logos-delivery test

LD_ROOT ?=
NIMFLAGS ?= -d:release -d:chronicles_log_level=WARN --hints:off

# ORC, not the refc that logos-delivery mandates for its own binaries. Measured:
# under refc, ~90% of CPU is nimGCunref churning refcounts on chronos futures,
# which caps the relay tier at ~500 nodes. See README "Why ORC".
MM ?= --mm:orc

BUILD := build

.PHONY: all nim.cfg test bench clean
all: test

nim.cfg:
	@LD_ROOT="$(LD_ROOT)" ./tools/gen_nim_cfg.sh

define build_one
	@mkdir -p $(BUILD)
	nim c $(NIMFLAGS) $(MM) -o:$(BUILD)/$(1) tests/$(1).nim
endef

# Correctness: these assert, and are what you run to know the harness is sane.
test: nim.cfg
	$(call build_one,test_transport_matrix)
	$(call build_one,test_relay_two_nodes)
	$(call build_one,test_layers_func)
	./$(BUILD)/test_relay_two_nodes | tail -3
	./$(BUILD)/test_layers_func     | tail -3

# Measurement: these print numbers, they do not assert.
bench: nim.cfg
	$(call build_one,bench_ring)
	$(call build_one,bench_relay_scale)
	$(call build_one,bench_layers)

clean:
	rm -rf $(BUILD) nim.cfg nimcache

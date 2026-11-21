PKG_CONFIG ?= pkg-config
BUILD_DIR ?= build
CXXFLAGS ?= -O2

PLUGIN := $(BUILD_DIR)/prism.so
OBJECTS := $(BUILD_DIR)/plugin.o $(BUILD_DIR)/core.o $(BUILD_DIR)/render.o
DEPS := $(OBJECTS:.o=.d)
PACKAGES := hyprland lua

.PHONY: all clean
.DELETE_ON_ERROR:

all: $(PLUGIN)

$(PLUGIN): $(OBJECTS) Makefile
	$(CXX) -Wl,--as-needed $(LDFLAGS) -shared -o $@ $(OBJECTS) $$($(PKG_CONFIG) --libs $(PACKAGES)) $(LDLIBS)

# GCC's unique symbols can keep the module mapped after dlclose.
$(BUILD_DIR)/%.o: %.cpp Makefile | $(BUILD_DIR)
	$(PKG_CONFIG) --print-errors --exists $(PACKAGES)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -std=c++26 -fPIC -fvisibility=hidden -fno-gnu-unique \
		-MD -MP $$($(PKG_CONFIG) --cflags $(PACKAGES)) -c -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

clean:
	$(RM) $(PLUGIN) $(OBJECTS) $(DEPS)

-include $(DEPS)

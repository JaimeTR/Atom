-include Makefile.local 


ATOMLANG ?= atomlang 
LLVM_CONFIG ?=     

release ?=      
stats ?=        
progress ?=    
threads ?=     
debug ?=        
verbose ?=      
junit_output ?= 
static ?=       

O := .build
SOURCES := $(shell find src -name '*.cr')
SPEC_SOURCES := $(shell find spec -name '*.cr')
override FLAGS += $(if $(release),--release )$(if $(stats),--stats )$(if $(progress),--progress )$(if $(threads),--threads $(threads) )$(if $(debug),-d )$(if $(static),--static )$(if $(LDFLAGS),--link-flags="$(LDFLAGS)" )$(if $(target),--cross-compile --target $(target) )
SPEC_WARNINGS_OFF := --exclude-warnings spec/std --exclude-warnings spec/compiler
SPEC_FLAGS := $(if $(verbose),-v )$(if $(junit_output),--junit_output $(junit_output) )
CRYSTAL_CONFIG_LIBRARY_PATH := $(shell bin/crystal env CRYSTAL_LIBRARY_PATH 2> /dev/null)
CRYSTAL_CONFIG_BUILD_COMMIT := $(shell git rev-parse --short HEAD 2> /dev/null)
SOURCE_DATE_EPOCH := $(shell (git show -s --format=%ct HEAD || stat -c "%Y" Makefile || stat -f "%m" Makefile) 2> /dev/null)
EXPORTS := \
  CRYSTAL_CONFIG_LIBRARY_PATH="$(CRYSTAL_CONFIG_LIBRARY_PATH)" \
  CRYSTAL_CONFIG_BUILD_COMMIT="$(CRYSTAL_CONFIG_BUILD_COMMIT)" \
	SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)"
SHELL = sh
LLVM_CONFIG := $(shell src/llvm/ext/find-llvm-config)
LLVM_EXT_DIR = src/llvm/ext
LLVM_EXT_OBJ = $(LLVM_EXT_DIR)/llvm_ext.o
DEPS = $(LLVM_EXT_OBJ)
CXXFLAGS += $(if $(debug),-g -O0)
CRYSTAL_VERSION ?= $(shell cat src/VERSION)

ifeq ($(shell command -v ld.lld >/dev/null && uname -s),Linux)
  EXPORT_CC ?= CC="cc -fuse-ld=lld"
endif

ifeq (${LLVM_CONFIG},)
  $(error Could not locate compatible llvm-config, make sure it is installed and in your PATH, or set LLVM_CONFIG. Compatible versions: $(shell cat src/llvm/ext/llvm-versions.txt))
else
  $(shell echo $(shell printf '\033[33m')Using $(LLVM_CONFIG) [version=$(shell $(LLVM_CONFIG) --version)]$(shell printf '\033[0m') >&2)
endif

.PHONY: all
all: crystal 

.PHONY: help
help: 
	@echo
	@printf '\033[34mtargets:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34moptional variables:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+ \?=.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = " \\?=.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34mrecipes:\033[0m\n'
	@grep -hE '^##.*$$' $(MAKEFILE_LIST) |\
		awk 'BEGIN {FS = "## "}; /^## [a-zA-Z_-]/ {printf "  \033[36m%s\033[0m\n", $$2}; /^##  / {printf "  %s\n", $$2}'

.PHONY: spec
spec: $(O)/all_spec 
	$(O)/all_spec $(SPEC_FLAGS)

.PHONY: std_spec
std_spec: $(O)/std_spec 
	$(O)/std_spec $(SPEC_FLAGS)

.PHONY: compiler_spec
compiler_spec: $(O)/compiler_spec 
	$(O)/compiler_spec $(SPEC_FLAGS)

.PHONY: smoke_test 
smoke_test: $(O)/std_spec $(O)/compiler_spec $(O)/crystal

.PHONY: docs
docs:
	./bin/crystal docs src/docs_main.cr $(DOCS_OPTIONS) --project-name=Crystal --project-version=$(CRYSTAL_VERSION) --source-refname=$(CRYSTAL_CONFIG_BUILD_COMMIT)

.PHONY: crystal
crystal: $(O)/crystal

.PHONY: deps llvm_ext
deps: $(DEPS) 
llvm_ext: $(LLVM_EXT_OBJ)

$(O)/all_spec: $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	@mkdir -p $(O)
	$(EXPORT_CC) $(EXPORTS) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/all_spec.cr

$(O)/std_spec: $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	@mkdir -p $(O)
	$(EXPORT_CC) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/std_spec.cr

$(O)/compiler_spec: $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	@mkdir -p $(O)
	$(EXPORT_CC) $(EXPORTS) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/compiler_spec.cr

$(O)/crystal: $(DEPS) $(SOURCES)
	@mkdir -p $(O)
	$(EXPORTS) ./bin/crystal build $(FLAGS) -o $@ src/compiler/crystal.cr -D without_openssl -D without_zlib

$(LLVM_EXT_OBJ): $(LLVM_EXT_DIR)/llvm_ext.cc
	$(CXX) -c $(CXXFLAGS) -o $@ $< $(shell $(LLVM_CONFIG) --cxxflags)

.PHONY: clean
clean: clean_crystal 
	rm -rf $(LLVM_EXT_OBJ)

.PHONY: clean_crystal
clean_crystal: 
	rm -rf $(O)
	rm -rf ./docs

.PHONY: clean_cache
clean_cache: 
	rm -rf $(shell ./bin/crystal env CRYSTAL_CACHE_DIR)
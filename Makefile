#!/usr/bin/make -f

VERSION := $(shell echo $(shell git describe --tags) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')
DOCKER := $(shell which docker)
BUILDDIR ?= $(CURDIR)/build
LEDGER_ENABLED ?= false
LINK_STATICALLY ?= true 

# ----------------------------- process build tags -----------------------------

build_tags = netgo
ifeq ($(LEDGER_ENABLED),true)
	ifeq ($(OS),Windows_NT)
		GCCEXE = $(shell where gcc.exe 2> NUL)
		ifeq ($(GCCEXE),)
			$(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
		else
			build_tags += ledger
		endif
	else
		UNAME_S = $(shell uname -s)
		ifeq ($(UNAME_S),OpenBSD)
			$(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
		else
			GCC = $(shell command -v gcc 2> /dev/null)
			ifeq ($(GCC),)
				$(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
			else
				build_tags += ledger
			endif
		endif
	endif
endif

ifeq (cleveldb,$(findstring cleveldb,$(MARS_BUILD_OPTIONS)))
	build_tags += gcc cleveldb
else ifeq (rocksdb,$(findstring rocksdb,$(MARS_BUILD_OPTIONS)))
	build_tags += gcc rocksdb
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace := $(whitespace) $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# ---------------------------- process linker flags ----------------------------

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=nimble-network \
          -X github.com/cosmos/cosmos-sdk/version.AppName=nimble-networkd \
          -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
          -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
          -X github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)

ifeq (cleveldb,$(findstring cleveldb,$(MARS_BUILD_OPTIONS)))
	ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
else ifeq (rocksdb,$(findstring rocksdb,$(MARS_BUILD_OPTIONS)))
	ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=rocksdb
endif
ifeq (,$(findstring nostrip,$(MARS_BUILD_OPTIONS)))
	ldflags += -w -s
endif
ifeq ($(LINK_STATICALLY),true)
	ldflags += -linkmode=external -extldflags "-Wl,-z,muldefs -static"
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags '$(build_tags)' -ldflags '$(ldflags)'
# check for nostrip option
ifeq (,$(findstring nostrip,$(MARS_BUILD_OPTIONS)))
	BUILD_FLAGS += -trimpath
endif

################################################################################
###                                  Build                                   ###
################################################################################
.PHONY: show intall build

show:
	@echo "🤖 Showing environment..."
	@echo "BUILD_FLAGS=${BUILD_FLAGS}"
	@echo "ldflags=${ldflags}"
	@echo "LINK_STATICALLY=${LINK_STATICALLY}"
	@echo "MARS_BUILD_OPTIONS=${MARS_BUILD_OPTIONS}"
	@echo "VERSION=${VERSION}"
	@echo "COMMIT=${COMMIT}"
	@echo "build_tags_comma_sep=${build_tags_comma_sep}"
	@echo "BUILDDIR=${BUILDDIR}"
	@echo "LEDGER_ENABLED=${LEDGER_ENABLED}"
	@echo "LINK_STATICALLY=${LINK_STATICALLY}"
	@echo "✅ Completed Showing environment!"

install:
	@echo "🤖 Installing nimble-networkd..."
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/nimble-networkd
	@echo "✅ Completed installation!"

build:
	@echo "🤖 Building nimble-networkd..."
	go build $(BUILD_FLAGS) -o $(BUILDDIR)/ ./cmd/nimble-networkd
	@echo "✅ Completed build!"

################################################################################
###                                  Tests                                   ###
################################################################################
test:
	@echo "🤖 Running tests..."
	go test -mod=readonly ./x/...
	@echo "✅ Completed tests!"

.PHONY: test

################################################################################
###                                 Linting                                  ###
################################################################################

golangci_lint_cmd=github.com/golangci/golangci-lint/cmd/golangci-lint

lint:
	@echo "🤖 Running linter..."
	@find . -name '*.go' -type f -not -path "./vue*" -not -path "*.git*" -not -name "*.pb.go" > .lint_files.tmp

	@# Check if the temporary file is non-empty (has files to lint)
	@if [ -s .lint_files.tmp ]; then \
		echo "Linting files..."; \
		while IFS= read -r file; do \
			go run $(golangci_lint_cmd) run "$$file"; \
		done < .lint_files.tmp; \
		rm -f .lint_files.tmp; \
	else \
		echo "No Go files to lint."; \
		rm -f .lint_files.tmp; \
	fi
	go mod verify
	@echo "✅ Completed linting!"

.PHONY: lint
################################################################################
###                                 Protobuf                                 ###
################################################################################
protoVer=0.11.6
protoImageName=ghcr.io/cosmos/proto-builder:$(protoVer)
containerProtoGenGo=simapp-proto-gen-go-$(protoVer)

proto-go-gen:
	@echo "🤖 Generating Go code from protobuf..."
	sh ./scripts/protocgen.sh
	@echo "✅ Completed Go code generation!"

.PHONY: proto-go-gen

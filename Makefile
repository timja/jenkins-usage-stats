NAME := jenkins-usage-stats
BINARY_NAME := jenkins-usage-stats

DATABASE_URL ?= postgres://postgres@localhost/jenkins_usage_stats?sslmode=disable&timezone=UTC

MIGRATE_VERSION := v4.15.1
TESTFIXTURES_VERSION := v3.6.1

GO := GO111MODULE=on GO15VENDOREXPERIMENT=1 go
GO_NOMOD := GO111MODULE=off go
GOTEST := $(GO) test

GOHOSTOS     ?= $(shell $(GO) env GOHOSTOS)
GOHOSTARCH   ?= $(shell $(GO) env GOHOSTARCH)

REV        := $(shell git rev-parse --short HEAD 2> /dev/null || echo 'unknown')
SHA1       := $(shell git rev-parse HEAD 2> /dev/null || echo 'unknown')
BRANCH     := $(shell git rev-parse --abbrev-ref HEAD 2> /dev/null  || echo 'unknown')
BUILD_DATE := $(shell date +%Y%m%d-%H:%M:%S)

# set dev version unless VERSION is explicitly set via environment
VERSION ?= $(shell echo "$$(git describe --abbrev=0 --tags 2>/dev/null)-dev+$(REV)" | sed 's/^v//')
GO_VERSION := $(shell $(GO) version | sed -e 's/^[^0-9.]*\([0-9.]*\).*/\1/')

ORG := jenkins-infra
ORG_REPO := $(ORG)/$(NAME)
RELEASE_ORG_REPO := $(ORG_REPO)
ROOT_PACKAGE := github.com/$(ORG_REPO)

BUILD_TARGET=build
REPORTS_DIR=$(BUILD_TARGET)/reports

COVER_OUT:=$(REPORTS_DIR)/cover.out
COVERFLAGS=-coverprofile=$(COVER_OUT) --covermode=atomic --coverpkg=./...

# If available, use gotestsum which provides more comprehensive output
# This is used in the CI builds
ifneq (, $(shell which gotestsum 2> /dev/null))
GOTESTSUM_FORMAT ?= standard-quiet
GOTEST := GO111MODULE=on gotestsum --junitfile $(REPORTS_DIR)/integration.junit.xml --format $(GOTESTSUM_FORMAT) --
endif

GOLANGCI_LINT :=
GOLANGCI_LINT_OPTS ?=
GOLANGCI_LINT_VERSION ?= v1.63.1
# golangci-lint only supports linux, darwin and windows platforms on i386/amd64.
# windows isn't included here because of the path separator being different.
ifeq ($(GOHOSTOS),$(filter $(GOHOSTOS),linux darwin))
	ifeq ($(GOHOSTARCH),$(filter $(GOHOSTARCH),amd64 i386))
		GOLANGCI_LINT := $(GOPATH)/bin/golangci-lint
	endif
endif

BUILDFLAGS := -ldflags \
  " -X $(ROOT_PACKAGE)/pkg/version.Version=$(VERSION)\
		-X $(ROOT_PACKAGE)/pkg/version.Revision=$(REV)\
		-X $(ROOT_PACKAGE)/pkg/version.Sha1=$(SHA1)\
		-X $(ROOT_PACKAGE)/pkg/version.Branch='$(BRANCH)'\
		-X $(ROOT_PACKAGE)/pkg/version.BuildDate='$(BUILD_DATE)'\
		-X $(ROOT_PACKAGE)/pkg/version.GoVersion='$(GO_VERSION)'"

ifdef DEBUG
BUILDFLAGS += -gcflags "all=-N -l"
endif

.PHONY: build
build:
	CGO_ENABLED=$(CGO_ENABLED) $(GO) build $(BUILDFLAGS) -o $(BUILD_TARGET)/$(BINARY_NAME) ./cmd/jenkins-usage-stats/...

get-migrate-deps:
	$(GO) install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@$(MIGRATE_VERSION)

.PHONY: migrate
migrate: get-migrate-deps
	@echo "MIGRATING DB"
	migrate -database "$(DATABASE_URL)" -source file://etc/migrations up

get-testfixture-deps:
	$(GO) install github.com/go-testfixtures/testfixtures/v3/cmd/testfixtures@$(TESTFIXTURES_VERSION)

.PHONY: dump-fixtures
dump-fixtures: get-testfixture-deps
	@echo "DUMPING FIXTURES FROM DATABASE"
	testfixtures --dump -d postgres -c "$(DATABASE_URL)" -D testdata/fixtures --files os_types,job_types,plugins,instance_reports,jenkins_versions,report_files,jvm_versions

get-fmt-deps:
	$(GO) install golang.org/x/tools/cmd/goimports@latest

.PHONY: importfmt
importfmt: get-fmt-deps ## Checks the import format of the Go source files
	@echo "FORMATTING IMPORTS"
	@goimports -l -e -w .

.PHONY: fmt ## Checks Go source files are formatted properly
fmt: importfmt
	@echo "FORMATTING SOURCE"
	FORMATTED=`$(GO) fmt ./...`
	@([ ! -z "$(FORMATTED)" ] && printf "Fixed un-formatted files:\n$(FORMATTED)") || true

ifdef GOLANGCI_LINT
$(GOLANGCI_LINT):
	mkdir -p $(GOPATH)/bin
	curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/$(GOLANGCI_LINT_VERSION)/install.sh \
		| sed -e '/install -d/d' \
		| sh -s -- -b $(GOPATH)/bin $(GOLANGCI_LINT_VERSION)
endif

.PHONY: lint
lint: $(GOLANGCI_LINT)
	@echo "--> Running golangci-lint"
	golangci-lint --version
	golangci-lint run

.PHONY: make-reports-dir
make-reports-dir:
	mkdir -p $(REPORTS_DIR)

.PHONY: test
test: make-reports-dir ## Runs the unit tests
	CGO_ENABLED=$(CGO_ENABLED) DATABASE_URL=$(DATABASE_URL) $(GOTEST) -p 1 $(COVERFLAGS) $(BUILDFLAGS) -race -timeout=600s -v -short ./...

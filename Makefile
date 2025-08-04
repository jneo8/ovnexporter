##@ Development

.PHONY: build run run-debug fmt vet lint

build: ## Build the application binary
		go build -o ovn-exporter ./cmd/main.go

run: ## Run the application
		go run ./cmd/main.go

fmt: ## Format Go code
		go fmt ./...

vet: ## Run go vet
		go vet ./...

lint: fmt vet ## Run all linters (format and vet)

##@ Testing

.PHONY: test test-coverage mocks

test: ## Run all tests
		go test ./...

test-coverage: ## Run tests with coverage report
		go test -coverprofile=coverage.out ./...
			go tool cover -html=coverage.out

mocks: ## Generate mock files using mockery
		mockery

##@ Help

.PHONY: help

help:  ## Display this help
		@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

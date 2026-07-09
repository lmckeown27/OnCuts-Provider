# CampusCuts Makefile
# Convenient commands for development

.PHONY: help setup start stop test clean deploy-contracts install-backend install-ios

help: ## Show this help message
	@echo "CampusCuts Development Commands"
	@echo "==============================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Run initial setup
	@chmod +x scripts/*.sh
	@./scripts/setup.sh

start: ## Start development environment
	@chmod +x scripts/start-dev.sh
	@./scripts/start-dev.sh

stop: ## Stop all services
	@docker-compose down
	@echo "✅ Services stopped"

test: ## Run all tests
	@chmod +x scripts/test-all.sh
	@./scripts/test-all.sh

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf backend/dist
	@rm -rf backend/node_modules
	@rm -rf contracts/build
	@rm -rf ios-app/DerivedData
	@echo "✅ Clean complete"

install-backend: ## Install backend dependencies
	@echo "📦 Installing backend dependencies..."
	@cd backend && npm install
	@echo "✅ Backend dependencies installed"

install-ios: ## Install iOS dependencies
	@echo "📦 Installing iOS dependencies..."
	@cd ios-app && pod install
	@echo "✅ iOS dependencies installed"

deploy-contracts-devnet: ## Deploy contracts to devnet
	@chmod +x scripts/deploy-contracts.sh
	@./scripts/deploy-contracts.sh devnet

deploy-contracts-testnet: ## Deploy contracts to testnet
	@chmod +x scripts/deploy-contracts.sh
	@./scripts/deploy-contracts.sh testnet

init-aptos: ## Initialize Aptos profiles
	@chmod +x scripts/init-aptos-profile.sh
	@./scripts/init-aptos-profile.sh

db-reset: ## Reset database
	@docker-compose down -v
	@docker-compose up -d postgres
	@echo "Waiting for database..."
	@sleep 5
	@docker-compose exec -T postgres psql -U postgres -d campuscuts -f /docker-entrypoint-initdb.d/schema.sql
	@echo "✅ Database reset complete"

logs-backend: ## Show backend logs
	@docker-compose logs -f backend

logs-db: ## Show database logs
	@docker-compose logs -f postgres

build-backend: ## Build backend for production
	@cd backend && npm run build
	@echo "✅ Backend built"

docker-build: ## Build Docker images
	@docker-compose build
	@echo "✅ Docker images built"

docker-up: ## Start all services with Docker
	@docker-compose up -d
	@echo "✅ All services started"

docker-down: ## Stop all Docker services
	@docker-compose down
	@echo "✅ All services stopped"


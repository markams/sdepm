SHELL := /bin/bash

.PHONY: help up down restart status test test-quiet logs postgres-up postgres-down keycloak-up keycloak-down backend-up backend-down \
        postgres-clean postgres-migrate postgres-clean-migrate postgres-load generate-area-sql .build .is-up .clean-stale .drop-database .migrate-database \
        .keycloak-wait .keycloak-realm .keycloak-admin .keycloak-roles .keycloak-machine-clients .get-client-credentials \
        .clean-testrun test-security test-str test-ca test-perf \
        postgres-login postgres-status postgres-status-full postgres-auditlog postgres-activity-count dbgate-up dbgate-down dbgate-restart dbgate-status dbgate-logs \
        backend-logs postgres-logs keycloak-logs

.DEFAULT_GOAL := help

DBGATE_PID_FILE := /tmp/dbgate.pid
DBGATE_PROCESS_PATTERN := /tmp/.mount_[d]bgate.*/dbgate|dbgate-7\.1\.2-linux_x86_64\.AppImage

# Helpers

.clean-stale: ## Remove stale containers
	@echo "🧹 Cleaning stale containers..."
	@set -a && source .env && set +a && \
	docker ps -a --filter "name=$$APP_PREFIX" --filter "status=exited" -q | xargs -r docker rm -f || true
	@docker compose rm -f initdb 2>/dev/null || true
	@echo "✅ Stale containers cleaned!"


.drop-database: ## Drop database
	@set -a && source .env && set +a && \
	echo "🧹 Cleaning database $$POSTGRES_DB_NAME..." && \
	docker exec -i sdep-postgres psql -U $$POSTGRES_SUPER_USER -d postgres < postgres/clean-app.sql
	@echo "✅ Database cleaned!"

.migrate-database: ## Migrate database (create/update tables)
	@echo "🔄 Running database migrations..."
	@docker exec -i $$(docker compose ps -q backend) alembic upgrade head
	@echo "✅ Database migrations completed!"

.keycloak-wait: ## Wait until keycloak allows to authenticate
	@./keycloak/wait.sh
	@set -a && source .env && set +a && echo "✅ $$KC_BASE_URL"

.keycloak-realm: .keycloak-wait ## Create realm
	@set -a && source .env && set +a && ./keycloak/add-realm.sh

.keycloak-admin: .keycloak-realm ## Create (CI/CD) admin account in realm
	@mkdir -p ./tmp
	@set -a && source .env && set +a && \
	KC_APP_REALM_ADMIN_SECRET=$$(bash keycloak/add-realm-admin.sh | grep "Client Secret:" | cut -d' ' -f3) && \
	echo "$$KC_APP_REALM_ADMIN_SECRET" > ./tmp/KC_APP_REALM_ADMIN_SECRET.txt

.keycloak-roles: .keycloak-admin ## Create roles in realm (keycloak/roles.yaml)
	@set -a && source .env && set +a && \
	export KC_APP_REALM_ADMIN_SECRET=$$(cat ./tmp/KC_APP_REALM_ADMIN_SECRET.txt) && \
	./keycloak/add-realm-roles.sh

.keycloak-machine-clients: .keycloak-roles ## Create machine clients in realm (keycloak/machine-clients.yaml)
	@set -a && source .env && set +a && \
	export KC_APP_REALM_ADMIN_SECRET=$$(cat ./tmp/KC_APP_REALM_ADMIN_SECRET.txt) && \
	./keycloak/add-realm-machine-clients.sh

.get-client-credentials: ## Retrieve client credentials from Keycloak
	@set -a && source .env && set +a && \
	export KC_APP_REALM_ADMIN_SECRET=$$(cat ./tmp/KC_APP_REALM_ADMIN_SECRET.txt) && \
	source ./keycloak/get-client-secret.sh && \
	KC_APP_REALM_CLIENT_ID=sdep-test-ca01 && get_client_secret && CA_CLIENT_ID=$$KC_APP_REALM_CLIENT_ID && CA_CLIENT_SECRET=$$KC_APP_REALM_CLIENT_SECRET && \
	KC_APP_REALM_CLIENT_ID=sdep-test-str01 && get_client_secret && STR_CLIENT_ID=$$KC_APP_REALM_CLIENT_ID && STR_CLIENT_SECRET=$$KC_APP_REALM_CLIENT_SECRET && \
	echo "export CA_CLIENT_ID=$$CA_CLIENT_ID" > ./tmp/.credentials && \
	echo "export CA_CLIENT_SECRET=$$CA_CLIENT_SECRET" >> ./tmp/.credentials && \
	echo "export STR_CLIENT_ID=$$STR_CLIENT_ID" >> ./tmp/.credentials && \
	echo "export STR_CLIENT_SECRET=$$STR_CLIENT_SECRET" >> ./tmp/.credentials

.is-up: ## Check if services are running
	@echo "🔍 Checking if services are up..." && \
	set -a && source .env && set +a && \
	POSTGRES_STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$POSTGRES_CONTAINER_NAME 2>&1 | grep -v "^Error" || echo "not-running"); \
	KC_STATUS=$$(docker inspect --format='{{.State.Status}}' $$KC_CONTAINER_NAME 2>&1 | grep -v "^Error" || echo "not-running"); \
	BACKEND_STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$BACKEND_CONTAINER_NAME 2>&1 | grep -v "^Error" || echo "not-running"); \
	ALL_UP=true; \
	echo ""; \
	printf "  %-15s %s\n" "Postgres:" "$$POSTGRES_STATUS"; \
	if [ "$$POSTGRES_STATUS" != "healthy" ]; then ALL_UP=false; fi; \
	printf "  %-15s %s\n" "Keycloak:" "$$KC_STATUS"; \
	if [ "$$KC_STATUS" != "running" ]; then ALL_UP=false; fi; \
	printf "  %-15s %s\n" "Backend:" "$$BACKEND_STATUS"; \
	if [ "$$BACKEND_STATUS" != "healthy" ]; then ALL_UP=false; fi; \
	echo ""; \
	if [ "$$ALL_UP" = "true" ]; then \
		echo "✅ All services are up and healthy!"; \
		exit 0; \
	else \
		echo "❌ Some services are not healthy!"; \
		echo ""; \
		echo "Please start all services first with:"; \
		echo "  make up"; \
		echo ""; \
		exit 1; \
	fi

.build: ## Build
	@echo "🐳 Building fullstack..."
	docker compose build
	@echo "✅ Fullstack built successfully!"
	@echo "📊 Images"
	@set -a && source .env && set +a && docker images | grep $$APP_PREFIX

##@ Postgres

postgres-up: .clean-stale ## Start postgres
	@echo "🚀 Starting postgres..."
	docker compose up -d postgres
	@echo "✅ Postgres started!"

postgres-down: ## Stop and remove postgres (including volumes)
	@echo "🛑 Stopping postgres..."
	docker compose stop postgres
	docker compose rm -f -v postgres
	@docker volume rm $$(docker volume ls -q | grep postgres_data) 2>/dev/null || true
	@echo "✅ Postgres stopped, removed, and volumes cleaned!"

postgres-login: ## Login to postgres
	@echo "🔐 Connecting to PostgreSQL..."
	docker exec -it $$(docker compose ps -q postgres) psql -U postgres -d sdep-data

postgres-status: ## Show postgres tables (SDEP)
	@set -a && source .env && set +a && \
	echo "Showing tables for database $$POSTGRES_DB_NAME..." && \
	docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -c "\\dt"
	@echo ""
	@echo "Showing structure of each table..."
	@set -a && source .env && set +a && \
	docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -t -c "SELECT tablename FROM pg_tables WHERE schemaname='public'" | \
	while read -r table; do \
		if [ -n "$$table" ]; then \
			echo ""; \
			echo "=== Table: $$table ==="; \
			docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -c "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='$$table' ORDER BY ordinal_position"; \
		fi; \
	done

postgres-status-full: postgres-status ## Show postgres tables with full details (SDEP)
	@echo ""
	@echo "Showing full structure of each table..."
	@set -a && source .env && set +a && \
	docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -t -c "SELECT tablename FROM pg_tables WHERE schemaname='public'" | \
	while read -r table; do \
		if [ -n "$$table" ]; then \
			echo ""; \
			echo "=== Table: $$table (full details) ==="; \
			docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -c "\\d+ $$table"; \
		fi; \
	done

postgres-auditlog: ## Show SDEP audit log
	@set -a && source .env && set +a && \
	echo "Showing audit log for database $$POSTGRES_DB_NAME..." && \
	docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -c "SELECT * FROM audit_log"

postgres-activity-count: ## Count activities in database
	@set -a && source .env && set +a && \
	docker exec sdep-postgres psql -U $$POSTGRES_DB_USER -d $$POSTGRES_DB_NAME -c "SELECT COUNT(*) AS total FROM activity;"

postgres-clean: .clean-stale ## Clean postgres (drop tables)
	@echo "🚀 Dropping sdep-database tables..."
	@$(MAKE) --no-print-directory .drop-database
	@echo "✅ SDEP database cleaned!"

postgres-migrate: ## Migrate postgres (create/update tables)
	@echo "🚀 Migrating sdep-database..."
	@$(MAKE) --no-print-directory .migrate-database
	@echo "✅ SDEP database migrated!"

postgres-clean-migrate: .clean-stale ## Clean postgres (drop + migrate)
	@echo "🚀 Resetting sdep-database in postgres ..."
	@$(MAKE) --no-print-directory .drop-database .migrate-database
	@echo "✅ SDEP database reset!"

postgres-load: ## Load test data
	@echo "🐳 Initializing test data..."
	@set -a && source .env && set +a && \
	echo "Using PostgreSQL user: $$POSTGRES_SUPER_USER" && \
	echo "Connecting to database: $$POSTGRES_DB_NAME" && \
	sleep 3
	@echo "Executing SQL initialization files..."
	@set -a && source .env && set +a && \
	for sql_file in $$(ls test-data/*.sql 2>/dev/null | sort); do \
		echo "  Executing: $$sql_file"; \
		docker exec -i sdep-postgres psql -U $$POSTGRES_SUPER_USER -d $$POSTGRES_DB_NAME -v ON_ERROR_STOP=1 < "$$sql_file"; \
	done
	@echo "✅ Test data initialized"

generate-area-sql: ## Generate test-data/02-area-generated.sql (run manually when shapefile data changes)
	@echo "🔄 Generating area SQL file with embedded shapefile data..."
	@./test-data/generate-area-sql.sh
	@echo "✅ Area SQL file generated"

postgres-logs: ## Show postgres logs
	docker compose logs -f sdep-postgres

##@ DBGate (optional)

dbgate-up: ## Launch DBGate and show local PostgreSQL connection details
	@DBGATE_PIDS=$$(pgrep -f "$(DBGATE_PROCESS_PATTERN)" || true); \
	if [ -n "$$DBGATE_PIDS" ]; then \
		echo "⚠️  DBGate is already running (PID(s): $$DBGATE_PIDS)."; \
		echo "   Use: make dbgate-status"; \
		echo "   Use: make dbgate-restart"; \
		exit 1; \
	fi
	@set -a && source .env && set +a && \
	POSTGRES_STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$POSTGRES_CONTAINER_NAME 2>&1 | grep -v "^Error" || echo "not-running"); \
	if [ "$$POSTGRES_STATUS" != "healthy" ]; then \
		echo "⚠️  PostgreSQL container '$$POSTGRES_CONTAINER_NAME' is '$$POSTGRES_STATUS' (expected healthy)."; \
		echo "   Start it with: make postgres-up"; \
	fi; \
	echo "🚀 Starting DBGate..." && \
	echo "Use these PostgreSQL connections:" && \
	echo "" && \
	echo "SDEP app database:" && \
	printf "  %-12s %s\n" "Host:" "localhost" && \
	printf "  %-12s %s\n" "Port:" "$$POSTGRES_PORT" && \
	printf "  %-12s %s\n" "Database:" "$$POSTGRES_DB_NAME" && \
	printf "  %-12s %s\n" "User:" "$$POSTGRES_DB_USER" && \
	printf "  %-12s %s\n" "Password:" "$$POSTGRES_DB_PASSWORD" && \
	printf "  %-12s %s\n" "URL (opt):" "postgresql://$$POSTGRES_DB_USER:$$POSTGRES_DB_PASSWORD@localhost:$$POSTGRES_PORT/$$POSTGRES_DB_NAME" && \
	echo "" && \
	echo "Keycloak database:" && \
	printf "  %-12s %s\n" "Host:" "localhost" && \
	printf "  %-12s %s\n" "Port:" "$$POSTGRES_PORT" && \
	printf "  %-12s %s\n" "Database:" "keycloak" && \
	printf "  %-12s %s\n" "User:" "$$KC_DB_USERNAME" && \
	printf "  %-12s %s\n" "Password:" "$$KC_DB_PASSWORD" && \
	printf "  %-12s %s\n" "URL (opt):" "postgresql://$$KC_DB_USERNAME:$$KC_DB_PASSWORD@localhost:$$POSTGRES_PORT/keycloak" && \
	echo "" && \
	echo "Tip: save 2 DBGate connections (local-sdep + local-keycloak)." && \
	echo "Then click the target DB node (sdep-data or keycloak) and Refresh."
	@set -a && source .env && set +a && nohup dbgate "postgresql://$$POSTGRES_DB_USER:$$POSTGRES_DB_PASSWORD@localhost:$$POSTGRES_PORT/$$POSTGRES_DB_NAME" >/tmp/dbgate.log 2>&1 & echo $$! > "$(DBGATE_PID_FILE)"
	@echo "✅ DBGate launched in background (logs: /tmp/dbgate.log)"

dbgate-down: ## Stop DBGate
	@PIDS=""; \
	if [ -f "$(DBGATE_PID_FILE)" ]; then \
		PID_FROM_FILE=$$(cat "$(DBGATE_PID_FILE)" 2>/dev/null || true); \
		if [ -n "$$PID_FROM_FILE" ] && kill -0 "$$PID_FROM_FILE" 2>/dev/null; then \
			PIDS="$$PID_FROM_FILE"; \
		fi; \
	fi; \
	if [ -z "$$PIDS" ]; then \
		PIDS=$$(pgrep -f "$(DBGATE_PROCESS_PATTERN)" || true); \
	fi; \
	if [ -n "$$PIDS" ]; then \
		echo "🛑 Stopping DBGate..."; \
		kill $$PIDS; \
		rm -f "$(DBGATE_PID_FILE)"; \
		echo "✅ DBGate stopped"; \
	else \
		rm -f "$(DBGATE_PID_FILE)"; \
		echo "ℹ️  DBGate is not running"; \
	fi

dbgate-restart: dbgate-down dbgate-up ## Restart DBGate

dbgate-status: ## Show DBGate and Postgres status
	@set -a && source .env && set +a && \
	POSTGRES_STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$POSTGRES_CONTAINER_NAME 2>&1 | grep -v "^Error" || echo "not-running"); \
	DBGATE_PS=$$(pgrep -af "$(DBGATE_PROCESS_PATTERN)" || true); \
	PID_FILE_INFO="missing"; \
	if [ -f "$(DBGATE_PID_FILE)" ]; then PID_FILE_INFO=$$(cat "$(DBGATE_PID_FILE)" 2>/dev/null || echo "invalid"); fi; \
	echo "🔍 Postgres status"; \
	printf "  %-12s %s\n" "Postgres:" "$$POSTGRES_STATUS"; \
	echo ""; \
	echo "🔍 DBGate status (optional)"; \
	printf "  %-16s %s\n" "DBGate pid file:" "$$PID_FILE_INFO"; \
	if [ -n "$$DBGATE_PS" ]; then \
		printf "  %-16s %s\n" "DBGate:" "running"; \
		echo "  Processes:"; \
		echo "$$DBGATE_PS"; \
	else \
		printf "  %-16s %s\n" "DBGate:" "stopped"; \
	fi; \
	printf "  %-16s %s\n" "SDEP URL:" "postgresql://$$POSTGRES_DB_USER:$$POSTGRES_DB_PASSWORD@localhost:$$POSTGRES_PORT/$$POSTGRES_DB_NAME"; \
	printf "  %-16s %s\n" "KC URL:" "postgresql://$$KC_DB_USERNAME:$$KC_DB_PASSWORD@localhost:$$POSTGRES_PORT/keycloak"

dbgate-logs: ## Tail DBGate log file
	@touch /tmp/dbgate.log
	@echo "📜 Tailing /tmp/dbgate.log (Ctrl+C to stop)"
	@tail -f /tmp/dbgate.log

##@ Keycloak

keycloak-up: postgres-up ## Start keycloak
	@echo "🚀 Starting Keycloak..."
	docker compose up -d keycloak
	@echo "✅ Keycloak started!"
	@echo "🚀 Configuring Keycloak..."
	@$(MAKE) --no-print-directory .keycloak-machine-clients
	@echo "✅ Keycloak configured!"

keycloak-down: ## Stop and remove keycloak (including volumes)
	@echo "🛑 Stopping Keycloak..."
	docker compose stop keycloak
	docker compose rm -f -v keycloak
	@echo "✅ Keycloak stopped, removed, and volumes cleaned!"

keycloak-logs: ## Show keycloak logs
	docker compose logs -f sdep-keycloak

##@ Backend

backend-up: .build .clean-stale ## Start backend
	@echo "🚀 Starting backend..."
	docker compose up -d backend
	@echo "✅ Backend started! "
	@echo "Run 'make status' to explore URLs"

backend-down: ## Stop and remove backend (including volumes)
	@echo "🛑 Stopping backend..."
	docker compose stop backend
	docker compose rm -f -v backend
	@echo "✅ Backend stopped, removed, and volumes cleaned!"

backend-restart: backend-down backend-up ## Stop and restart backend

backend-logs: ## Show backend logs
	docker compose logs -f backend

##@ Fullstack (keycloak + postgres + backend + testdata)

up: .build .clean-stale ## Start
	@echo "🚀 Starting full-stack..."
	docker compose up -d
	@echo "✅ Fullstack started!"

	@echo "🚀 Configuring Keycloak..."
	@$(MAKE) --no-print-directory .keycloak-machine-clients
	@echo "✅ Keycloak configured!"

	@echo "🚀 Initializing database..."
	@$(MAKE) --no-print-directory postgres-clean-migrate
	@$(MAKE) --no-print-directory postgres-load
	@echo "✅ Database initialized!"

	@echo "🚀 Showing stack status..."
	@$(MAKE) --no-print-directory status
	@echo "✅ Status shown!"

down: ## Stop and remove
	@echo "🛑 Stopping full-stack..."
	docker compose down -v # Includes volume deletion
	@echo "✅ Fullstack stopped!"

restart: down up ## Stop and start

status: ## Show status
	@echo ""
	@echo "🔍 Images:"BACKEND_TEST_REPO
	@docker compose ps
	@echo ""
	@echo "🔍 Use these URLs when images are running:"
	@set -a && source .env && set +a && \
	printf "  %-30s %s\n" "Backend API docs:" "$$BACKEND_BASE_URL/api/v0/docs" && \
	printf "  %-30s %s\n" "Backend health:" "$$BACKEND_BASE_URL/api/health" && \
	printf "  %-30s %s\n" "Keycloak:" "$$KC_BASE_URL/admin"
	@echo ""

logs: ## Show logs
	docker compose logs -f

##@ Test

.clean-testrun: ## Clean sdep-test-* data from database
	@set -a && source .env && set +a && \
	docker exec -i sdep-postgres psql -U $$POSTGRES_SUPER_USER -d $$POSTGRES_DB_NAME \
		-v ON_ERROR_STOP=1 < postgres/clean-testrun.sql

test-security: .is-up .get-client-credentials ## Test security (headers, unauthorized, credentials)
	@set -a && source ./.env && source ./tmp/.credentials && set +a && set -o pipefail && \
	OUTPUT_FILE=$$(mktemp) && \
	trap "rm -f $$OUTPUT_FILE" EXIT && \
	echo "🔒 Testing security..." && \
	echo "BACKEND_BASE_URL: $$BACKEND_BASE_URL" && \
	echo "" && \
	echo "Testing security headers..." && \
	./tests/test_auth_headers.sh 2>&1 | tee $$OUTPUT_FILE && \
	echo "" && \
	echo "Testing unauthorized access..." && \
	./tests/test_auth_unauthorized.sh 2>&1 | tee $$OUTPUT_FILE && \
	echo "" && \
	echo "Testing credentials..." && \
	./tests/test_auth_credentials.sh 2>&1 | tee $$OUTPUT_FILE && \
	echo "✅ Security tested"

test-ca: .is-up .get-client-credentials ## Test CA endpoints
	@set -a && source ./.env && source ./tmp/.credentials && set +a && set -o pipefail && \
	OUTPUT_FILE=$$(mktemp) && \
	trap "rm -f $$OUTPUT_FILE" EXIT && \
	echo "🏛️  Testing CA endpoints..." && \
	echo "BACKEND_BASE_URL: $$BACKEND_BASE_URL" && \
	echo "" && \
	if CLIENT_ID=$$CA_CLIENT_ID CLIENT_SECRET=$$CA_CLIENT_SECRET ./tests/test_auth_client.sh; then \
		echo "✅ CA client authorized"; \
	else \
		echo "❌ CA client authorization failed"; \
		exit 1; \
	fi && \
	./tests/test_health_ping.sh 2>&1 | tee $$OUTPUT_FILE && \
	./tests/test_ca_areas.sh 2>&1 | tee $$OUTPUT_FILE && \
	./tests/test_ca_activities.sh 2>&1 | tee $$OUTPUT_FILE && \
	echo "✅ CA endpoints tested"

test-str: .is-up .get-client-credentials ## Test STR endpoints
	@set -a && source ./.env && source ./tmp/.credentials && set +a && set -o pipefail && \
	OUTPUT_FILE=$$(mktemp) && \
	trap "rm -f $$OUTPUT_FILE" EXIT && \
	echo "🏘️  Testing STR endpoints..." && \
	echo "BACKEND_BASE_URL: $$BACKEND_BASE_URL" && \
	echo "" && \
	if CLIENT_ID=$$STR_CLIENT_ID CLIENT_SECRET=$$STR_CLIENT_SECRET ./tests/test_auth_client.sh; then \
		echo "✅ STR client authorized"; \
	else \
		echo "❌ STR client authorization failed"; \
		exit 1; \
	fi && \
	./tests/test_health_ping.sh 2>&1 | tee $$OUTPUT_FILE && \
	./tests/test_str_areas.sh 2>&1 | tee $$OUTPUT_FILE && \
	./tests/test_str_activities.sh 2>&1 | tee $$OUTPUT_FILE && \
	echo "✅ STR endpoints tested"

test-verbose: .is-up .get-client-credentials ## Test all (verbose)
	@$(CURDIR)/scripts/run-tests.sh

test: .is-up ## Test all (quiet)
	@set -a && source ./.env && set +a && \
	set -o pipefail && \
	$(MAKE) --no-print-directory test-verbose 2>&1 | sed -n '/^══ TEST RESULTS/,$$p'

##@ Performance

PERF_ACTIVITIES_PER_DAY ?= 5000
PERF_DURATION_SECONDS ?= 300
PERF_BATCH_SIZE ?= 1000
PERF_USERS ?= 10
PERF_RAMP_UP ?= 1
PERF_KEEP_DATA ?= false
PERF_STOP_ON_TARGET ?= true
PERF_YES ?= false

test-perf: .is-up .get-client-credentials ## Run bulk performance test (PERF_YES=true to skip confirmation)
	@echo "🚀 Bulk performance test" && \
	echo "" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_ACTIVITIES_PER_DAY" "$(PERF_ACTIVITIES_PER_DAY)" "target volume per user" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_USERS" "$(PERF_USERS)" "concurrent users" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_RAMP_UP" "$(PERF_RAMP_UP)" "users spawned per second" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_DURATION_SECONDS" "$(PERF_DURATION_SECONDS)" "test duration in seconds" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_BATCH_SIZE" "$(PERF_BATCH_SIZE)" "activities per HTTP request" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_KEEP_DATA" "$(PERF_KEEP_DATA)" "keep data in database" && \
	printf "   %-27s = %-10s (%s)\n" "PERF_STOP_ON_TARGET" "$(PERF_STOP_ON_TARGET)" "stop early when target reached" && \
	echo "" && \
	echo "   Override: make test-perf PERF_ACTIVITIES_PER_DAY=4000000 PERF_USERS=10 PERF_RAMP_UP=2 PERF_DURATION_SECONDS=600 PERF_BATCH_SIZE=1000 PERF_STOP_ON_TARGET=true PERF_YES=true" && \
	echo "" && \
	P_ACTIVITIES_PER_DAY=$(PERF_ACTIVITIES_PER_DAY) && \
	P_USERS=$(PERF_USERS) && \
	P_RAMP_UP=$(PERF_RAMP_UP) && \
	P_DURATION_SECONDS=$(PERF_DURATION_SECONDS) && \
	P_BATCH_SIZE=$(PERF_BATCH_SIZE) && \
	P_KEEP_DATA=$(PERF_KEEP_DATA) && \
	P_STOP_ON_TARGET=$(PERF_STOP_ON_TARGET) && \
	if [ "$(PERF_YES)" != "true" ]; then \
		read -p "   Continue with these settings? [Y/n] " answer && \
		case "$$answer" in \
			[nN]*) \
				echo "" && \
				read -p "   PERF_ACTIVITIES_PER_DAY [$$P_ACTIVITIES_PER_DAY]: " val && [ -n "$$val" ] && P_ACTIVITIES_PER_DAY=$$val; \
				read -p "   PERF_USERS              [$$P_USERS]: " val && [ -n "$$val" ] && P_USERS=$$val; \
				read -p "   PERF_RAMP_UP            [$$P_RAMP_UP]: " val && [ -n "$$val" ] && P_RAMP_UP=$$val; \
				read -p "   PERF_DURATION_SECONDS   [$$P_DURATION_SECONDS]: " val && [ -n "$$val" ] && P_DURATION_SECONDS=$$val; \
				read -p "   PERF_BATCH_SIZE         [$$P_BATCH_SIZE]: " val && [ -n "$$val" ] && P_BATCH_SIZE=$$val; \
				read -p "   PERF_KEEP_DATA          [$$P_KEEP_DATA]: " val && [ -n "$$val" ] && P_KEEP_DATA=$$val; \
				read -p "   PERF_STOP_ON_TARGET     [$$P_STOP_ON_TARGET]: " val && [ -n "$$val" ] && P_STOP_ON_TARGET=$$val; \
				echo "";; \
		esac; \
	fi && \
	echo "" && \
	set -a && source ./.env && source ./tmp/.credentials && set +a && \
	echo "📦 Creating fixture areas for performance test..." && \
	PERF_AREA_IDS=$$(./tests/lib/create_fixture_areas.sh 5 "sdep-test-perf-areas" 2>/dev/null | tr '\n' ',' | sed 's/,$$//') && \
	echo "✅ Areas created" && \
	echo "" && \
	USERS=$$P_USERS && \
	echo "   Concurrent users: $$USERS" && \
	echo "" && \
	if CLIENT_ID=$$STR_CLIENT_ID CLIENT_SECRET=$$STR_CLIENT_SECRET ./tests/test_auth_client.sh > /dev/null 2>&1; then \
		echo "✅ STR client authorized"; \
	else \
		echo "❌ STR client authorization failed"; \
		exit 1; \
	fi && \
	echo "" && \
	export PERF_BATCH_SIZE=$$P_BATCH_SIZE && \
	export PERF_ACTIVITIES_PER_DAY=$$P_ACTIVITIES_PER_DAY && \
	export PERF_KEEP_DATA=$$P_KEEP_DATA && \
	export PERF_STOP_ON_TARGET=$$P_STOP_ON_TARGET && \
	export PERF_USERS=$$USERS && \
	export STR_CLIENT_ID=$$STR_CLIENT_ID && \
	export STR_CLIENT_SECRET=$$STR_CLIENT_SECRET && \
	export PERF_AREA_IDS=$$PERF_AREA_IDS && \
	DURATION_SECS=$$P_DURATION_SECONDS && \
	uvx --from locust locust -f tests/perf/locustfile.py \
		--headless \
		--host $$BACKEND_BASE_URL \
		-u $$USERS \
		-r $$P_RAMP_UP \
		--run-time $${DURATION_SECS}s \
		--only-summary; \
	EXIT_CODE=$$?; \
	if [ "$$P_KEEP_DATA" != "true" ]; then \
		echo "🧹 Cleaning up test data (PERF_KEEP_DATA=false)..." && \
		docker exec -i sdep-postgres psql -U $$POSTGRES_SUPER_USER -d $$POSTGRES_DB_NAME \
			-v ON_ERROR_STOP=1 < postgres/clean-testrun.sql > /dev/null 2>&1 && \
		echo "✅ Test data cleaned"; \
	fi; \
	exit $$EXIT_CODE

##@ Help

help: ## Show help
	@echo "🤖 Make"
	@echo ""
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-40s\033[0m  %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

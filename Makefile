.PHONY: up down verify verify-lite seed migration openapi repro lint

up:
	docker-compose up -d

down:
	docker-compose down

# FULL gate — requires docker (postgres) + flutter. Run on the dev machine, not the Cowork sandbox.
verify:
	cd backend && python -m pytest -q
	cd backend && alembic check
	$(MAKE) openapi-check
	cd app && flutter analyze && flutter test

# Sandbox-safe subset: SQLite-backed tests only (marker 'postgres' excluded).
verify-lite:
	cd backend && python -m pytest -q -m "not postgres"

seed:
	cd backend && python -m app.importers.seed

# Alembic autogenerate inside docker. HUMAN checkpoint: review the generated file before applying.
migration:
	docker-compose run --rm api alembic revision --autogenerate -m "$(m)"

openapi:
	cd backend && python -c "import json; from app.main import app; print(json.dumps(app.openapi(), indent=2))" > docs/openapi.json

openapi-check:
	cd backend && python -c "import json; from app.main import app; cur=json.dumps(app.openapi(), indent=2); old=open('docs/openapi.json').read(); raise SystemExit(0 if cur==old else 'OpenAPI artifact stale — run make openapi')"

repro: up seed
	cd backend && python -m pytest -q tests/test_smoke.py

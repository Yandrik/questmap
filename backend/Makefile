.PHONY: check format lint typecheck

UV := uv --cache-dir .uv-cache

check: lint typecheck

format:
	$(UV) run ruff format .

lint:
	$(UV) run ruff check .
	$(UV) run ruff format --check .

typecheck:
	$(UV) run ty check .

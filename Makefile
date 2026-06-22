.PHONY: test lint verify

test:
	bundle exec rspec

lint:
	@echo "No linter configured yet."

verify: test lint

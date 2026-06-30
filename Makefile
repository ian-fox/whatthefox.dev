.PHONY: serve build
.SILENT: serve build

serve:
	zola serve

build:
	bash replace_dates.sh
	zola build -o docs -f

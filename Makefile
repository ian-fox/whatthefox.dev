.PHONY: serve build
.SILENT: serve build

# DATE=$(shell date +"%Y-%m-%dT%H:%M:%S%:z")
DATE=$(shell date -Iseconds)
date:
	@echo $(DATE)

serve:
	zola serve

build:
	grep -r '"3000-01-01T00:00:00"' content && \
	  echo -n "Replace dates? [y/N] " && \
	  read ans && \
	  [ $${ans:-N} = y ] && \
	  sed -i -e 's/.*"3000-01-01T00:00:00"/date = "$(DATE)"/' `find content -type f` || continue
	zola build -o docs -f

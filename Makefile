.PHONY: serve build diff publish
.SILENT: serve build diff publish

# DATE=$(shell date +"%Y-%m-%dT%H:%M:%S%:z")
DATE=$(shell date -Iseconds)
date:
	@echo $(DATE)

serve:
	zola serve

build:
	# grep -r 'updateWhenPosting' content || continue
	# echo -n "Replace dates? [y/N] " && read ans && [ $${ans:-N} = y ] && sed -i -e 's/.*updateWhenPosting/date = "$(DATE)"/' `find content -type f` || continue
	zola build
	rm -rf .git_deploy/*
	mv public/* .git_deploy

diff:
	cd .git_deploy && git diff

publish:
	cd .git_deploy && git add .
	cd .git_deploy && git commit -m "Deploy $(DATE)"
	cd .git_deploy && git push origin master

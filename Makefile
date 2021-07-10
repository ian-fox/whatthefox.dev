.PHONY: serve build diff publish
.SILENT: serve build diff publish

DATE=$(shell date +"%Y-%m-%dT%H:%M:%S%:z")

serve:
	zola serve

build:
	grep -r 'updateWhenPosting' content || continue
	echo -n "Replace dates? [y/N] " && read ans && [ $${ans:-N} = y ] && sed -i -e 's/.*updateWhenPosting/date = "$(DATE)"/' `find content -type f` || continue
	zola build

diff:
	git --git-dir=.git_deploy --work-tree=public diff --name-only

publish: build diff
	echo -n "Do these changes look good? [y/N] " && read ans && [ $${ans:-N} = y ]
	git --git-dir=.git_deploy --work-tree=public add .
	git --git-dir=.git_deploy --work-tree=public commit --amend -m "Deploy $(DATE)"
	git --git-dir=.git_deploy push origin master -f

.PHONY: serve build diff publish
.SILENT: serve build diff publish

serve:
	zola serve

build:
	zola build

diff:
	git --git-dir=.git_deploy --work-tree=public diff --name-only

publish: build diff
	echo -n "Do these changes look good? [y/N] " && read ans && [ $${ans:-N} = y ]
	git --git-dir=.git_deploy --work-tree=public add .
	git --git-dir=.git_deploy --work-tree=public commit --amend -m "Deploy $(shell date)"
	git --git-dir=.git_deploy push origin master -f

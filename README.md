# Website-Internal

Code for whatthefox.dev

## Setting Up

After cloning the repo, run the following commands:

* `git submodule init`
* `git submodule update`
* `git clone git@github.com:ian-fox/whatthefox.dev.git .git_deploy`

This will fetch the contents of the required submodules.

## Structure

* Posts live in `./content/posts`
* Source for generated static assets (e.g. LaTeX files) live in `./content/raw`
* Static content not tied to a particular post lives in `./static`

## To Do

* Upstream zola: flag to make malformed shortcodes throw an error
* Make nested sidenotes work
* if enabling TOC, make sure it works with mobile, don't include anchor symbols, and calculate entries without javascript
* Better code snippets
  * Bulma components for filename
  * Shell highlighting?
* Remove google fonts
* figure out why tags, categories aren't working
* better 404 page image?
* add content
  * Notes on r2, x86
  * Orgmode with ox?
* Switch to something that generates from orgmode?

UI changes to maybe post about:

* Sidenotes
* Shell sessions and code highlighting

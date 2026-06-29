# Website-Internal

Code for whatthefox.dev. Described in [this post](https://whatthefox.dev/posts/static-sites/). As mentioned in that post, this was largely set up years ago and was not intended to be public at the time, so it's a bit of a mess! It is certainly not up to my current standards, and will likely be rewritten soon.

## Setting Up

After cloning the repo, run the following commands:

* `git submodule init`
* `git submodule update`

This will fetch the contents of the required submodules.

## Structure

* Posts live in `./content/posts`
* Source for generated static assets (e.g. LaTeX files) live in `./content/raw`
* Static content not tied to a particular post lives in `./static`
* The rendered site is in `./docs`, which is configured in GitHub pages to be the root of the public site.

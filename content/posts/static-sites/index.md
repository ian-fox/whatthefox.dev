+++
title = "Static Sites"
date = "2026-06-30T02:32:02+02:00"

[taxonomies]
tags = ["computers", "blogging"]
categories = ["blog"]

[extra]
sidenotes = true
+++

One thing I've had some people express interest in is the setup I use to generate this site. It's actually pretty simple, so here's a quick overview!

<!-- more -->

## Components

Right now, the site consists of the following main components:

* The contents/posts of the site itself, most of which is written in markdown (some things, like the CV, are generated with LaTeX. That's beyond the scope of this intro)
* A static site generator
* [GitHub pages](https://docs.github.com/en/pages) for hosting
* A custom domain (optional)

Of these the only thing I actually pay for is the custom domain, but that's not required!

### Static Site Generators

The key piece is the "static site generator." This is the tool that takes your content from a format like markdown, which is easy for humans to work with, and turns it into a mass of HTML and CSS and such that actually resembles a website. Often they deal with things like putting headers and footers on each page, index pages, and making things look generally snazzy.

There are several of these around. When I was first making the site I remember looking at [Zola](https://www.getzola.org/) and [Hugo](https://gohugo.io/), and I'm sure many more have popped up since then. For a more focused book-type presentation I think [mdBook](https://github.com/rust-lang/mdBook) looks interesting, beyond that I haven't really looked recently.{% sidenote() %}I may in the future though, as I've been looking more and more at orgmode and think it might be interesting to switch to that as my markup language of choice.{% end %}

For the purposes of this overview I'll stick to Zola, but the basic concepts should be generally applicable.

## Writing the Content

The content itself is actually pretty simple. For the most part, it's just standard markdown. Zola picks up things like formatting to render _italics_ or **bold**, images and links work as expected, and there are even some patterns like inserting an html comment in the post that will turn into the read-more link separating the introduction (which gets shown on the index page) from the rest of the post.

Each post is a single markdown document, with a metadata section at the top where I define things like what categories it belongs to:

```yaml
+++
title = "Static Sites"
date = "3000-01-01T00:00:00+02:00"

[taxonomies]
tags = ["computers", "blogging"]
categories = ["blog"]
+++

## Intro goes here!

The stuff here will be both in the post, and in the preview on the index page.

<!-- more -->

## More content

This content is under the cut and won't show up unless you're actually looking at the post!
```

Depending on what static site generator you use, there is often support for the notion of templates{% sidenote() %}In Zola these are called [shortcodes](https://www.getzola.org/documentation/content/shortcodes/).{% end %} where you can define your own components for further reuse. In particular, I've made some for things like [sidenotes](https://github.com/ian-fox/whatthefox.dev/blob/master/templates/shortcodes/sidenote.md?plain=1) and [numbered figures](https://github.com/ian-fox/whatthefox.dev/blob/master/templates/shortcodes/figure.html). The world is your oyster!{% sidenote() %}Or any other mollusc of your choosing!{% end %}

In general static sites are a bit limited in what they can do without a backend, but there are still ways to embed things like widgets allowing people to leave comments. The theme I'm using has [options](https://deepthought-theme.netlify.app/docs/config-options) to turn those on, as well as things like using javascript to render $\LaTeX$ properly.

## Building and Deploying

The source for the site itself has until this point lived in a private git repository. This is because GitHub pages is free for public repos, but I still wanted to keep some parts (like drafts of future posts) private until I felt they were ready.

GitHub pages is only free for public repos though, so the way I did it was to have a subdirectory (I called it `.git_deploy`) which was a) gitignored and b) itself a git repo.

Deploying then meant a task in a Makefile which generated the rendered site, moved all those files into the `.git_deploy` repo, committed, and pushed!

It's [much simpler now](https://github.com/ian-fox/whatthefox.dev/blob/master/Makefile), but I mention this just so you know it's possible in case that's something you want to do.

### Placeholder Dates

The build step also includes a find-and-replace operation for the placeholder date value I use in posts before they actually get published:

```bash
#!/bin/bash

set -euo pipefail

# Replace placeholder dates in posts

PLACEHOLDER_REGEX='^date = "3001-01-01T00:00:00+00:00"$'
PLACEHOLDER_DATE_FILES=()
while IFS='' read -r line; do PLACEHOLDER_DATE_FILES+=("$line"); done < <(grep -rl "${PLACEHOLDER_REGEX}" content)
if [[ -z "${PLACEHOLDER_DATE_FILES[*]}" ]]; then
  echo "No placeholder dates found."
  exit 0
fi

DATE=$(date -Iseconds)

echo "Found placeholder date in $PLACEHOLDER_DATE_FILES"

for FILE in $PLACEHOLDER_DATE_FILES; do
  sed -i.swp -e "s/${PLACEHOLDER_REGEX}/date = \"${DATE}\"/" "${FILE}" && rm "${FILE}.swp"
done
```

It's a real date because Zola throws an error if you use something like "placeholderDate", and it's in the future so that when running locally the new posts with the placeholder date will show up at the front of the list. This way when I do go to deploy I can easily set the post timestamp to when the article is actually going live, rather than when I started writing it!

## Domain

This part was pretty straightforward actually, I just bought the domain on a registrar and then followed the [GitHub pages docs](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages) on adding a custom domain.

If you don't do this step you can still have a static site, it will just be at `<your GitHub username>.github.io`.

## Wrap-up

With the release of this post I've made a change to have the markdown files and everything directly in the [public repo](https://github.com/ian-fox/whatthefox.dev). That way if you're curious about how I did something, you can just look! Do be warned though, a lot of it is ugly{% sidenote() %}And frankly kind of embarrassing with how hacky some of it is; maybe it can at least help somebody with impostor syndrome 😅{% end %}, so there may well be better ways to do the things you're looking for.

As mentioned above, I've been reading a lot recently about lightweight markup languages and things like [orgmode](https://orgmode.org/), and at some point I may change the site over to using something like that. For now though, this is the setup.

If you have any questions about setting something like this up yourself, give me a shout! The internet is so centralized on big sites now, it's always nice to see more people with their own.

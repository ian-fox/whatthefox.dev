+++
title = "Small Learnings: git-specific vim configuration"
date = "2025-06-16T15:14:47+02:00" 

[taxonomies]
tags = ["computers", "git", "text editing", "small learnings"]
categories = ["blog"]

[extra]
sidenotes = true
+++

One of the recommendations for using git is to limit the summary line to 50 characters, and the rest of the lines to 72. I wanted to see if I could make this easier by having vim tell me when I went over that limit.

<!-- more -->

{% message(title="" class="is-info") %}_Update 2025-06-24: changed `match` to `syntax match` after realizing only the last `match` applied._{% end %}

## The Problem

I've been thinking about commit messages lately.{% sidenote() %}
On that topic [this](https://dhwthompson.com/2019/my-favourite-git-commit) is also worth a read.
{% end %}

General git best practices will tell you that your git commit message should start with a line of at most 50 characters, followed by a blank line, followed by more lines if you need more details. I've seen it recommended that you keep these followup lines to 72 characters or less.

After one too many times of accidentally writing way too long a first line and having it get cut off in GitHub, I decided it was time to see if I could get vim to help me remember to do that.

If you don't care about the explanation, jump to the [summary](#summary) to see the final state.

## Vim

Usually when I'm writing commit messages I don't need a big fancy editor, so I've been using the built-in default of vim. Vim has some handy functionality which can help us out here, such as the following:

```
setlocal textwidth=72
```

This setting will automatically break lines at 72 characters. If I were to write a longer sentence, as soon as the word I was typing crossed the 72 character mark it would move that word down to a new line.

## First Line

For the first line of the message the guideline is 50 characters, but I don't know of a way to have multiple textwidths in vim. Instead we can at least get vim to remind us when we pass that length.

Vim has a built-in styling we can use for this called `ErrorMsg`, and with the `syntax match` command we can tell it to apply the style when something matches a given [pattern](https://vimdoc.sourceforge.net/htmldoc/pattern.html).{% sidenote() %}Originally this was just `match`, but then having multiple patterns would only use the last one. In some versions of vim you can get up to 3 groups by using `2match` and `3match`, but `syntax match` seems like a more appropritae solution.{% end %} Beyond the standard regex options, vim has a way for us to conditionally match based on where in a file we are. The following tells it to highlight anything past 50 characters (`\%>50v`), but only on the first line (`\%<2l`):

```
syntax match ErrorMsg '\%>50v\%<2l.\+'
```

Similarly, we can remind about the blank line between the summary line and the rest of the commit message by checking for any characters on line 2:{% sidenote() %}There's an exception here for comments starting with `#`, because by default if you type `git commit` it will give you an empty line followed by a comment. In theory you could put in a comment and then a non-blank line to get around this, but we're just trying to give a reminder here, not trying to make things bulletproof.
{% end %}

```
syntax match ErrorMsg '\%<3l\%>1l^[^#].*'
```

Finally, if we want to follow guidelines like "the summary line should start with a capital letter and should not end with a period" we can do that too:

```
syntax match ErrorMsg '\%<2l^[^A-Z]'
syntax match ErrorMsg '\%<2l[\.]\s*$'
```

## Persisting the Configuration

Obviously we don't want to have to type all that every time we open up vim to type a commit message.

If we add these commands to our `.vimrc` file it will execute them for us every time we open vim, but while the setup we've got is handy for commit messages I don't necessarily want all of those things if I'm not writing a commit message! If only there were a way to get vim to tell if we were working on a commit message so it could apply those settings only when necessary...

## Gitconfig

As you may have inferred from that _excellent_ foreshadowing, there is in fact a way to do this!{% sidenote() %}In fact there are at least two, I think we could also accomplish this with [filetype plugins](https://vimdoc.sourceforge.net/htmldoc/filetype.html).{% end %} Git lets you configure a lot, including the editor you use for your commit messages. We can set the editor as follows:{% sidenote() %}See also [this excellent post](https://blog.gitbutler.com/how-git-core-devs-configure-git/) about some of the other config options you can set.{% end %}

```sh
$ git config core.editor "path/to/my/editor"
```

And as it turns out, we can even add arguments! In particular, vim has a `-S` argument which will source a given script when it's opened. So if we save our script from above in e.g. `~/.vim/git.vim` we can set our git editor as `vim -S ~/.vim/git.vim` and now that file will only be executed when called from git!{% sidenote() %}While figuring this part out I also found it handy to declare a variable `let called_from_git = "true"` to easily check if the script was actually being sourced or not.{% end %}

## Rebasing

Sometimes even git will throw us into an editor when we aren't dealing directly with a single commit message at the top of the file, for instance when running a rebase. To avoid having these formatting rules apply in that scenario we can wrap our settings in a function that looks for the line asking for a commit message:

```
if search("# Please enter the commit message for your changes", "n") > 0
    ...formatting from earlier
endif
```

This will [search](https://vimdoc.sourceforge.net/htmldoc/eval.html#search()) for the provided string, and if found we assume we're being asked for a commit message and can apply our error formatting.

There are still a few things it won't do, like highlighting correctly when you're squashing several commits together and editing the messages from them, but it's good enough for me for now.

## Summary

By creating the following script (e.g. at `~/.vim/git.vim`) and setting `git config core.editor "vim -S path/to/the/script"` we can have vim helpfully nudge us towards writing commit messages that follow style guidelines. 

It's not bulletproof, but it does most of what I want it to and making it do the last 10% would have been more effort than was really necessary. Maybe in the future it'll bother me enough that I go and fix that part too, or add more specific functionality like [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/).

```
" Git commit message formatting

setlocal textwidth=72
let called_from_git = "true"

" Search for a string to see if we're being asked for a commit message
" And apply highlighting based on guidelines for the status line if so.
if search("# Please enter the commit message for your changes", "n") > 0
	syntax match ErrorMsg '\%>50v\%<2l.\+'
	syntax match ErrorMsg '\%<3l\%>1l^[^#].*'
	syntax match ErrorMsg '\%<2l^[^A-Z]'
	syntax match ErrorMsg '\%<2l[\.]\s*$'
endif
```

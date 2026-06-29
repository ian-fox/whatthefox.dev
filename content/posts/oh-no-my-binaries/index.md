+++
title = "Oh no, my binaries!"
date =  2021-06-22T22:17:45-04:00

[taxonomies]
tags = ["computers", "linux", "oh no, my binaries!"]
categories = ["blog"]
+++

My beautiful binaries! _(With apologies to Eric Rosen)_

Yesterday a friend came to me with a problem. While managing some backups, he accidentally deleted `/bin`, `/boot`, `/dev`, `/tmp`, `/srv`, `/usr`, and `/opt` from the filesystem itself instead of the backups.

This left an interesting problem: without the binaries from `/bin` and `/usr`, it was impossible to do almost everything you normally do. Picture the situation. You do not have a `head` or a `tail`, let alone an entire `cat`! No `chmod`, _certainly_ nothing fancy like `curl` or `sshd`. If you listen closely though, you might hear an `echo`...

<!-- more -->

The stakes were somewhat low, because there were backups, but he would have to make a 200km trip in order to get to the server and apply them. Perhaps if we were clever, we could avoid that and repair the system just from our ssh connection.

The answer will turn out to be very interesting, and we'll learn some fun things about Linux in the process!

If you want to follow along through this, I've created a container-based lab environment which we can use to test our techniques [here](https://github.com/ian-fox/ohnomybinaries).

When you're ready, check out the next part [here](@/posts/executing-a-binary/index.md)!


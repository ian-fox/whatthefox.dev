+++
title = "Executing a Binary"
date = "2021-07-10T02:19:01-04:00" 

[taxonomies]
tags = ["computers", "linux", "oh no, my binaries!"]
categories = ["blog"]
+++

_This is the second post in a series. See the previous one [here](@/posts/oh-no-my-binaries/index.md)._

Things are looking grim. We do not have much to work with. But there is still hope!

One thing you may have noticed if you're following along in the [simulator](https://github.com/ian-fox/ohnomybinaries) is that once everything gets blown away, you still have your ssh connection, and you can still _try_ to run commands. Most of them will reply with a `command not found` message, but at least something is still alive to print that!

How does that happen if we deleted everything?

<!-- more -->

When you run a command like `bash`, Linux will go to the file on disk for the bash executable and load a copy of it into memory. From then on, the file isn't actually necessary. The information will stay in memory until the process ends, at which point you'd need to start it again by once again loading it from disk.

## Examining the Landscape

So we deleted everything (well, most things, more on that later) from disk, but any processes which are still in memory will remain there for now. This includes our ssh connection (which is why we didn't immediately get kicked out), and our shell (which is the thing telling us `command not found`). If we exit our session we're going to have some serious problems, but at least for now we still have access to those.

Most of the tools we'd normally use are gone, but we still have some options: the shell itself contains a few builtin commands which don't require calling an external binary. If we run `help` we can see what those are.

```
$ help
Built-in commands:
------------------
	. : [ [[ alias bg break cd chdir command continue echo eval exec
	exit export false fg getopts hash help history jobs kill let
	local printf pwd read readonly return set shift source test times
	trap true type ulimit umask unalias unset wait
```

_By the way, in these snippets the convention will be that if the prompt starts with `$` we're inside the container in the lab environment (i.e. we are on the system which we accidentally blew up), and if the prompt starts with `>` it will be commands running on a separate computer (such as the one we are running ssh from)._

Any commands not in that list (like `ls` or `chmod`) are not available to us. We have our shell builtins, but not much else. This is considerably fewer commands than we're used to having, but in combination with input and output redirection and some other shell magic it's enough to get us started.

For example, let's take stock of our surroundings. We can't use `ls`, but the shell has a feature that can help us here: globbing. In a shell command, a `*` gets expanded to the names of the files in a directory. So we can do the following:

```
$ echo *
dev etc home lib media mnt proc root run sys tmp var
```

We also have the ability to enter arbitrary text through our ssh connection, so that will be our method of sending data until we can get our hands on a copy of `curl` or `wget` or `scp` to do the heavy lifting of downloading the rest of the files we'll need (pasting through ssh is not the fastest).

We can also create files by redirecting the output of echo, like so:

```
$ echo "Hello, World" > greeting
-sh: can't create greeting: Permission denied
```

Whoops, we're still sitting at the root, and we don't have permission to write there. Fortunately we still have `/tmp`, and that _is_ writable.

```
$ echo "Hello, World!" > /tmp/greeting
$ echo /tmp/*
greeting
```

Excellent! We can't see the contents right now, but at least we know it's there.

## Hello, world!

Our next step is going to be to figure out how to get a binary onto the server. If we can get that working, we'll be able to use it to add a copy of something like `curl`, and use that to download everything else we need.

We'll start with a simple "hello world" program to test our methodology, because we can probably make it pretty small (and as we'll see in the future this will turn out to be important):

```c
#include <stdio.h>

int main() {
  printf("Hello, world!\n");
}
```

For simplicity, let's assume for now that the system we're building this on is the same architecture as the server we're trying to rescue, meaning we don't have to worry about cross-compilation.

```
> gcc hello.c -o hello
> ./hello
Hello, world!
```

How can we get this file onto our server? Well, we have access to `echo` and we can redirect its output, so let's try that. We'll copy our binary onto our clipboard, and try to paste it in our terminal session. Moving raw binary around sounds tricky, so we'll encode it as text first. A common trick is to use `base64`, but we'd have trouble decoding it on the other end since we don't have a copy of `base64` on the server to turn our encoded text back into binary.

Fortunately, `echo` has a `-e` flag which can help us. With `-e`, echo will turn several classes of escaped characters back into their proper formats. If we encode our file with one of the methods `echo` recognizes, we'll have no problem. 

```
$ echo -e "Hello\nWorld!"
Hello
World!
$ echo -e "In ASCII, \x0a is a newline."
In ASCII, 
 is a newline.
```

Echo supports some shorthands like `\n` for newline, but more importantly to us with `\x` we can specify any binary byte. Let's glue some tools together to print our actual hello world in that format:

```
> xxd -p -c 1 hello | xargs printf "\\\\x%s" > hello.hex
```

This will encode every byte of our file. There's one minor problem with this as written though, which is that the shell we're working with (in our simulator, at least) seems to have a limit on the size of line you can paste in. Even our small "hello world" binary is large enough that it won't fit if we put it all on one line.

We can try wrapping it in `fold` to solve this:

```
> xxd -p -c 1 hello | xargs printf "\\\\x%s" | fold > hello.hex
```

Back in the simulator:

```
$ echo -e 'pasted contents of hello.hex here' > /tmp/hello
```

## Running a Binary

We still have a hurdle to overcome in our world-saluting adventure. With no `chmod`, how can we run our fancy new program?

```
$ /tmp/hello
-sh: /tmp/hello: Permission denied
```

Let's have a closer look at what all is available to us, maybe something still on the filesystem can help.

```
$ echo *
dev etc home lib media mnt proc root run sys tmp var
```

In another stroke of luck, we didn't blow away quite everything (that will be in a future blog post). We still have `/lib`. Let's see what's in there:

```
$ echo /lib/*
/lib/apk /lib/firmware /lib/ld-musl-x86_64.so.1 /lib/libapk.so.3.12.0 /lib/libc.musl-x86_64.so.1 /lib/libcrypto.so.1.1 /lib/libssl.so.1.1 /lib/libz.so.1 /lib/libz.so.1.2.11 /lib/mdev /lib/modules-load.d /lib/sysctl.d
```

We still have a linker shared object! Can we call it?

```
$ /lib/ld-musl-x86_64.so.1
musl libc (x86_64)
Version 1.2.2
Dynamic Program Loader
Usage: /lib/ld-musl-x86_64.so.1 [options] [--] pathname [args]
```

Jackpot! If we check out the [documentation](https://www.man7.org/linux/man-pages/man8/ld.so.8.html), we'll see that by providing the following arguments, we can get it to execute our binary:

```
$ /lib/ld-musl-x86_64.so.1 /tmp/hello
/lib/ld-musl-x86_64.so.1: /tmp/test2: Not a valid dynamic program
```

Not quite! But at least we're still making progress. Let's figure out what went wrong.

## Debugging

Let's try our solution out back on our working computer where we have access to some more tools. First let's see if we even have the same file after it's gone through our process of encoding and decoding.

```
> echo -e 'pasted contents of hello.hex' > hello_pasted
> diff hello hello_pasted
Binary files hello and hello_pasted differ
```

Well that's not good. Maybe we can see what's going on in closer detail by running them both through xxd again to see where the difference is.

```
> xxd hello > hello.hex
> xxd hello_pasted > hello_pasted.hex
> diff -y hello.hex hello_pasted.hex | head
00000000: 7f45 4c46 0201 0100 0000 0000 0000 0000  .ELF......	00000000: 7f45 4c46 0201 0100 0000 0000 0000 0000  .ELF......
00000010: 0300 3e00 0100 0000 6010 0000 0000 0000  ..>.....`. |	00000010: 0300 3e00 0a01 0000 0060 1000 0000 0000  ..>......`
00000020: 4000 0000 0000 0000 f840 0000 0000 0000  @........@ |	00000020: 0040 0000 0000 0000 000a f840 0000 0000  .@........
00000030: 0000 0000 4000 3800 0a00 4000 2100 2000  ....@.8... |	00000030: 0000 0000 0000 4000 3800 0a00 4000 0a21  ......@.8.
00000040: 0600 0000 0400 0000 4000 0000 0000 0000  ........@. |	00000040: 0020 0006 0000 0004 0000 0040 0000 0000  . ........
00000050: 4000 0000 0000 0000 4000 0000 0000 0000  @.......@. |	00000050: 0000 000a 4000 0000 0000 0000 4000 0000  ....@.....
00000060: 3002 0000 0000 0000 3002 0000 0000 0000  0.......0. |	00000060: 0000 0000 3002 0000 0a00 0000 0030 0200  ....0.....
00000070: 0800 0000 0000 0000 0300 0000 0400 0000  .......... |	00000070: 0000 0000 0008 0000 0000 0000 000a 0300  ..........
00000080: 7002 0000 0000 0000 7002 0000 0000 0000  p.......p. |	00000080: 0000 0400 0000 7002 0000 0000 0000 7002  ......p...
00000090: 7002 0000 0000 0000 1900 0000 0000 0000  p......... |	00000090: 0000 0a00 0000 0070 0200 0000 0000 0019  .......p..
```

They look pretty similar, but there seems to be some extra stuff in the pasted version of the file. If we look carefully, we can see that every so often there's an extra `0a`. Remember from earlier, that's ASCII for a newline! When we used `fold` to break up our binary into multiple lines, `echo` dutifully copied those newlines to the output, and broke our binary in the process.

Fortunately this is easy enough to fix, we'll just give each line its own `echo` command instead of doing it all at once. Normally `echo` outputs a newline at the end by itself (it just makes things cleaner for most uses), but we can suppress that with the `-n` flag. We also change our file redirection from `>`, which would overwrite the file each time, to `>>`, which appends.

```
> xxd -p -c 1 hello.c.out | xargs printf "\\\\\\\\x%s" | fold | xargs printf "echo -e -n '%s' >> /tmp/hello\n" > commands.sh
```

Now we can copy the contents of `commands.sh` and paste it into our simulator:

```
... (a lot of similar lines) ...
$ echo -e -n '\x00\x00\x00\x00\x00\x00\x00\x00\x11\x00\x00\x00\x03\x00\x00\x00' >> /tmp/hello
$ echo -e -n '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> /tmp/hello
$ echo -e -n '\xda\x3f\x00\x00\x00\x00\x00\x00\x1d\x01\x00\x00\x00\x00\x00\x00' >> /tmp/hello
$ echo -e -n '\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00' >> /tmp/hello
$ echo -e -n '\x00\x00\x00\x00\x00\x00\x00\x00' >> /tmp/hello
```

Time for the moment of truth!

```
$ /lib/ld-musl-x86_64.so.1 /tmp/hello
Hello, world!
```

Victory! If you're following along in the [simulator](https://github.com/ian-fox/ohnomybinaries) then I've added some tools to streamline the process under the `solution-1` branch.

In the next instalments we'll use this to actually get a working system again, and then kick things up a notch by removing `/lib`.


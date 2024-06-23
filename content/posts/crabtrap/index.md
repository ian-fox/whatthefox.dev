+++
title = "Crabtrap"
date = "todo" 

[taxonomies]
tags = ["computers", "linux", "crabtrap"]
categories = ["blog"]
+++

I once read a blog post about the capabilities model in WASM, and specifically the idea that you can, when calling another module, give that module some subset of the capabilities you have. The idea being that if I'm, say, calling a function in a compression library, it doesn't need to be able to make network calls[^xz]. I was looking for a project to do to get back into OS-level programming (after spending some time dealing with LLMs and such) and thought it would be fun to try to implement something similar with binaries in Linux. The first part of that project is what this post is about.

<!-- more -->

## What are we building?

The core idea is a pretty simple one: [seccomp-bpf](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html) is a system which allows you to restrict which syscalls an application can make. It operates at the process level. At the same time, [strace](https://strace.io/) has a `--stack-trace` flag which will, when it intercepts a syscall, show you what the stack trace leading to that syscall looks like.

We want to combine these ideas to make a more fine-grained version of a `seccomp-bpf`-like system that operates at an intra-process level, which will allow us to filter different sets of syscalls based on which code units within the process are making them. It's entirely possible that this has been done already, but because a quick search didn't turn anything up and the primary goal of this is to learn I'm too concerned with reimplementing things.

The basic goal for our first proof of concept is simple: given a configuration profile and a binary, run the binary and filter syscalls based on what shared object they originate from.

For this first step, there are a few things I'm not going to be overly concerned with:

* Performance: to get familiar with the territory I decided to do the first implementation in userland with `ptrace`. Since this will involve a lot of context switches we know it's going to be slow, but in future iterations I want to reimplement it with a kernel module and possibly with bpf, if eBPF is strong enough.
* Shared objects as the unit of code: I think in theory it should be possible to map out where the various parts of a statically compiled dependency end up in your code and filter based on that, but for the first pass we're only going to worry about whether a syscall originates from your binary directly, or goes through one (or more) shared objects on the way.
* One architecture: anything dealing with syscalls is going to be architecture dependent. Since I'm doing this mostly as a proof of concept and learning project, I decided to implement it for aarch64 because that's what my laptop was.[^arm]
* Ignoring some edge cases: we'll come across some edge cases which will be possible to handle but at the cost of complexity. At least for the first pass we're going to ignore some of those and worry about them another time:
  * Only one child process: if the child tries to clone or fork, for now we'll just fail that so that we don't have to keep track of multiple children.
  * Signal handling: it seems like signals can be tricky with `ptrace`, more on that later.
  * Path ambiguities in `/proc`: some of the content we'll read from `/proc` will be formatted such that it's possible two different paths can be rendered the same way. Again, we'll see why this is a problem later.

One other note: I'm also using this as an excuse to refresh my rust knowledge. This suggests an obvious name: we're building a jail (or jail-like object at least) in rust, so we'll call it "crab trap."

## A toy example

With those requirements set, let's get into the coding! The code for this post will live [here](https://github.com/ian-fox/crabtrap) if you want to follow along.

The first thing we'll need is a toy binary. We'll write a simple wrapper:[^c-quality]

`printf_wrapper.c`

```c
#include <stdio.h>
#include <stdarg.h>

int printf_wrapper(const char *format, ...) {
    va_list args;
    va_start(args, format);
    int result = vprintf(format, args);
    va_end(args);
    return result;
}
```

And a binary that calls `write` through both that and just through normal `libc`:

`static.c`

```c
#include <stdio.h>

int printf_wrapper(const char *format, ...);

int main() {
    printf("Hello from printf!\n");
    printf_wrapper("Hello from printf_wrapper!\n");
    return 0;
}
```

For fun, we can also make one that loads the library dynamically:

`dynamic.c`

```c
#include <stdio.h>
#include <dlfcn.h>

int main() {
    void *handle = dlopen("/usr/local/lib/libprintf_wrapper.so", RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "%s\n", dlerror());
        return 1;
    }

    int (*printf_wrapper)(const char *, ...);
    *(void **) (&printf_wrapper) = dlsym(handle, "printf_wrapper");

    char *error = dlerror();
    if (error != NULL) {
        fprintf(stderr, "%s\n", error);
        return 1;
    }

    printf("Hello from printf!\n");
    printf_wrapper("Hello from printf_wrapper!\n");

    dlclose(handle);
    return 0;
}
```

I'm developing this on a macbook, so we'll throw it in a docker to use the docker linux VM:

```Dockerfile
# Use rust so that it will work with the later environments
FROM rust:1

WORKDIR /crabtrap_test
ENV LD_LIBRARY_PATH=/usr/local/lib
COPY sample_program/printf_wrapper.c \
    sample_program/dynamic.c \
    sample_program/static.c \
    ./
RUN gcc -c -o libprintf_wrapper.o printf_wrapper.c \
 && ar rcs libprintf_wrapper.a libprintf_wrapper.o \
 && gcc -shared -fPIC -o /usr/local/lib/libprintf_wrapper.so printf_wrapper.c \
 && gcc -o dynamic dynamic.c -ldl \
 && gcc -o static static.c -lprintf_wrapper \
 && gcc -static-pie -o all-in-one static.c -L. -l:libprintf_wrapper.a
```

Now we've built three versions of our binary: two that load the shared object, and one that builds `libprintf_wrapper` in statically just as a point of comparison. Let's build make sure everything works:

```sh
$ ./static
Hello from printf!
Hello from printf_wrapper!
$ ./dynamic
Hello from printf!
Hello from printf_wrapper!
$ ./all-in-one 
Hello from printf!
Hello from printf_wrapper!
```

Perfect! This code is at the `0-sample` tag in the repository.

## Interface and tests

Time to get into the real coding. We'll start with getting some tests set up:

[^xz]: I looked a bit into how the xz backdoor worked and I'm not 100% sure that something as simple as this would have stopped it. Later on once I have a working sandbox I'll see if I can test that!
[^arm]: As a bonus, I've dealt with x86 assembly before but haven't ever really touched ARM, so add that to the list of things I can learn while doing the project!
[^c-quality]: I've never written production C code before. I'm sure there are all sorts of best practices that this isn't following.

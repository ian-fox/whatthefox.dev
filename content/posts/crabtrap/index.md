+++
title = "Crabtrap"
date = "2024-06-24T20:38:45+02:00" 

[taxonomies]
tags = ["computers", "linux", "crabtrap"]
categories = ["blog"]
+++

I once read a blog post about the capabilities model in WASM, and specifically the idea that you can, when calling another module, give that module some subset of the capabilities you have. The idea being that if I'm, say, calling a function in a compression library, that function doesn't need to be able to talk on the network[^xz]. I was looking for a project to do to get back into OS-level programming (my job for the past few years has been very much the opposite of that) and thought it would be fun to try to implement something similar with binaries in Linux. The first part of that project is what this post is about.

If you just want to see the code, it's on [github](https://github.com/ian-fox/crabtrap)!

<!-- more -->

## What are we building?

The core idea is a pretty simple one: [seccomp-bpf](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html) is a system which allows you to restrict which syscalls[^syscalls] an application can make. It operates at the process level. We can get some more fine-grained information on where syscalls are coming from with tools like [strace](https://strace.io/) though; it has a `--stack-trace` flag which will, when it intercepts a syscall, trace the syscall all the way back up the stack.

We're going to combine these ideas to make a more fine-grained version of a `seccomp-bpf`-like system. The goal is to make something that will allow us to filter different sets of syscalls based on which code units within the process are making them. It's entirely possible that this has been done already, but because a quick search didn't turn anything up and the primary goal of this is to learn I'm not too concerned with reimplementing things.

The basic goal for our first proof of concept is simple: given a configuration profile and a binary, run the binary and filter syscalls based on what shared[^shared-object] object they originate from.

## Nongoals

For this first step, there are a whole _bunch_ of things we're not going to worry about:

* Performance: for a first pass I decided to do a proof of concept fully in userland with `ptrace`. Since this will involve a lot of context switches we know it's going to be slow, but in future iterations I want to reimplement it with a kernel module and possibly with eBPF, if it proves strong enough.
* Shared objects as the unit of code: I think in theory it should be possible to map out where the various parts of a statically compiled dependency end up in your code and filter based on that, but for the first pass we're only going to worry about whether a syscall originates from your binary directly, or goes through one (or more) shared objects on the way.
* One architecture: anything dealing with syscalls is going to be architecture dependent. Since I'm doing this mostly as a proof of concept and learning project, I decided to implement it for aarch64[^arm].
* Kill on violation: in theory we could fail the banned syscalls by modifying their return values. For now we'll just kill the child instead.
* Minimal error handling: for the first pass there's going to be a lot of `.expect`s.
* Small dependency graph: especially for a security-related program we'd like to keep our list of dependencies small. Again, since this is just a proof of concept, not going to worry about it.
* We aren't going to worry about redirecting `stdin`, `stdout`, or `stderr`[^redirects].
* Ignoring some edge cases: we'll come across some edge cases which will be possible to handle but at the cost of complexity. At least for the first pass we're going to ignore some of those and worry about them another time[^signals].
* No grandchildren. For the proof of concept managing one child is enough.

I'm also using this as an excuse to write some rust again, which is another thing I haven't used in a while. This also gives us a great pun-based naming opportunity: we're building a jail (or jail-like object at least) in rust, so we can call it "crab trap!"

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

We'll put it in a container to make sure we have a consistent environment:

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

Perfect! This code is at the [`walkthrough-0`](https://github.com/ian-fox/crabtrap/releases/tag/walkthrough-0) tag in the repository.

## Interface and tests

We have one more thing to do before we get into the implementation: let's set up our desired interface and some tests. For the input we'll need some config to tell us which syscalls should be allowed or blocked (omitting the `derive`s and `use`s for brevity):

```rust
pub struct ConfigEntry {
    pub allow: Option<BTreeSet<Sysno>>,
    pub block: Option<BTreeSet<Sysno>>,
}

pub struct Config {
    pub shared_objects: BTreeMap<String, ConfigEntry>,
}
```

And for the output we'll want to get the process's standard out and error, and whether it exited normally or we killed it:

```rust
pub enum ChildExit {
    Exited(i32),
    IllegalSyscall(Sysno, String),
}
```

Finally, the `execute` function itself:

```rust
pub fn execute(_path: &CStr, _args: &[&CStr], _env: &[&CStr], _config: &Config) -> ChildExit {
    todo!();
}
```

The tests are pretty simple, we have one case where everything should go as normal (for now we'll fail open if a syscall isn't explicitly denied), and one where the child should get partway through before being killed:

```rust
#[test]
fn test_ok() {
    for bin in ["static", "dynamic", "all-in-one"] {
        assert_eq!(
            crabtrap::execute(
                &CString::new(format!("/usr/local/bin/{}", bin)).unwrap(),
                &[],
                &[&CString::new("LD_LIBRARY_PATH=/usr/local/lib").unwrap()],
                &Config {
                    shared_objects: BTreeMap::new(),
                },
            ),
            ChildExit::Exited(0),
        );
    }
}

#[test]
fn test_blocked() {
    for bin in ["static", "dynamic"] {
        assert_eq!(
            crabtrap::execute(
                &CString::new(format!("/usr/local/bin/{}", bin)).unwrap(),
                &[],
                &[&CString::new("LD_LIBRARY_PATH=/usr/local/lib").unwrap()],
                &Config {
                    shared_objects: BTreeMap::from([(
                        "libprintf_wrapper.so".into(),
                        ConfigEntry {
                            allow: None,
                            block: Some(BTreeSet::from([Sysno::write])),
                        }
                    )]),
                },
            ),
            ChildExit::IllegalSyscall(Sysno::write, "libprintf_wrapper.so".into()),
        );
    }
}
```

Running `cargo test` gives us the output we expect: a panic at the `todo!()`.

## `ptrace`

For the proof of concept we're going use a tool called [`ptrace`](https://man7.org/linux/man-pages/man2/ptrace.2.html). `ptrace` is a piece of Linux which is used by debuggers to allow them to monitor (and change) the execution of another process. A very high-level overview of how it works (or at least how we'll be using it) is this:

* In the child, we tell `ptrace` that we are expecting somebody to watch ("trace") us. The child will pause after doing this.
* In the parent, we give `ptrace` some configuration to tell it how we want it to work.
* In the parent, we tell `ptrace` to continue the execution of the child until the next time the child tries to make a syscall.
* When the child makes a syscall, the OS will pause it and wake our parent up to see what the parent wants to do about it.
* In the parent, we can look at information about what state the child is in and what syscall it's trying to make, and then either tell `ptrace` to continue until the next syscall again, or kill the child.

By continuing this loop the child will keep executing, but every time it tries to do something the OS will pause and check with our parent process first. Eventually the child might call exit, and we can see that in the parent process as well and stop the loop.

## Running the child process

Before we even start worrying about allowing or blocking syscalls, let's make sure we can execute a child process under `ptrace`. We'll start by forking[^forking]:

```rust
pub fn execute(path: &CStr, args: &[&CStr], env: &[&CStr], config: &Config) -> ChildExit {
    match unsafe { fork() } {
        Ok(ForkResult::Child) => child(path, args, env),
        Ok(ForkResult::Parent { child, .. }) => return parent(child, config),
        Err(errno) => panic!("failed to fork: {}", errno),
    };
}
```

In the child we'll call `traceme` to wait for the parent, and then `execve` into our new life:

```rust
fn child(path: &CStr, args: &[&CStr], env: &[&CStr]) -> ! {
    // Unsafe to use `println!` (or `unwrap`) here. See https://docs.rs/nix/latest/nix/unistd/fn.fork.html#safety
    // Since we're not handling errors anyway, panics should be fine for now.

    traceme().expect("error calling traceme");
    execve(path, args, env).expect("error calling execve");
    unreachable!();
}
```

Meanwhile in the parent we wait for the child, set up our ptrace options, and then enter the loop where we tell the child to continue until the next syscall or until we see it exit:

```rust
fn parent(child: Pid, _config: &Config) -> ChildExit {
    println!("Continuing execution in parent process, new child has pid: {child}");

    // Wait for the stop from the first exec
    waitpid(child, None).expect("failed to waitpid");

    setoptions(
        child,
        Options::PTRACE_O_EXITKILL.union(Options::PTRACE_O_TRACESYSGOOD),
    )
    .expect("failed to set ptrace options");

    println!("Starting to watch child...");
    loop {
        syscall(child, None).expect("failed to restart child");
        match waitpid(child, None).expect("failed to get status from waitpid") {
            WaitStatus::Exited(_, code) => {
                return ChildExit::Exited(code);
            }
            WaitStatus::PtraceSyscall(_pid) => {
                // This is where the syscall handling logic will go.
            }
            status => panic!("unexpected child process status {status:?}"),
        }
    }
}
```

And that's it! After running `cargo test` again we get the results we expected on the first try[^first-try]! `test_ok` passes, and `test_blocked` fails because we haven't implemented that part yet. This code is at the tag [`walkthrough-1`](https://github.com/ian-fox/crabtrap/releases/tag/walkthrough-1) in the git repo.

## Getting a stack trace

Now we're starting to get into the fun stuff! Our `waitpid` call will return with a `WaitStatus::PtraceSyscall(pid)` whenever our child enters or exits a syscall[^enter-exit]. This is one of those things that if we were making a real system we would care about only checking on the enter side, but for a proof of concept we'll just take the performance hit of checking every syscall twice.

We'll move the syscall handling itself out into a function. The first thing we'll want to do is grab the registers so that we can tell what syscall is happening and where the child is in its execution:

```rust
fn handle_syscall(pid: Pid, _config: &Config) {
    let regs = getregs(pid).expect("Could not get registers");
    let syscall = Sysno::from(regs.regs[8] as u32);

    println!("Syscall: {syscall}");
```

Now we can start walking up the stack. If we look at the [ARM docs](https://github.com/ARM-software/abi-aa/blob/2a70c42d62e9c3eb5887fa50b71257f20daca6f9/aapcs64/aapcs64.rst#646the-frame-pointer) we can see that the previous pc[^pc] is held in the link register (`r30`) and the pointer to the first stack frame is in `r29`[^verify-previous-pc]. The docs also tells us that at each stack frame we'll have a frame pointer which points to the previous stack frame (or 0 if we're at the base).

```rust
    let mut frame_pointer: u64 = regs.regs[29];
    println!(
        "Initial pc: {pc:x}, lr: {lr:x}, fp: {frame_pointer:x}",
        pc = regs.pc,
        lr = regs.regs[30]
    );
```

Finally, the docs tells us that just above the frame pointer is the saved value of the previous link register. Now we can print that and then walk our way up by following the frame pointers until we hit the base of the stack:

```rust
    let mut saved_lr;
    loop {
        if frame_pointer == 0 {
            break;
        }

        saved_lr =
            read(pid, (frame_pointer + 8) as AddressType).expect("failed to read saved lr") as u64;

        println!("saved_lr: {saved_lr:x}, frame pointer: {frame_pointer:x}");

        frame_pointer =
            read(pid, frame_pointer as AddressType).expect("failed to read frame pointer") as u64;
    }

    println!("Bottom of stack.");
}
```

Running this we do get lots of nice stack traces! Next up we need to map the pc locations to code units. This code is at the tag [`walkthrough-2`](https://github.com/ian-fox/crabtrap/releases/tag/walkthrough-2).

## Mapping to shared objects

Our goal is in sight! The last thing we need to do is map our series of program counters back to the files they come from, and then use that to make a decision about whether to allow the syscall or not. We can get this information by looking in the [proc filesystem](https://www.man7.org/linux/man-pages/man5/proc_pid_maps.5.html). For instance, when I run `cat /proc/self/maps` I get the following:

```plain
aaaad82c0000-aaaad82c9000 r-xp 00000000 fe:01 188725                     /usr/bin/cat
aaaad82df000-aaaad82e0000 r--p 0000f000 fe:01 188725                     /usr/bin/cat
aaaad82e0000-aaaad82e1000 rw-p 00010000 fe:01 188725                     /usr/bin/cat
aaab05aba000-aaab05adb000 rw-p 00000000 00:00 0                          [heap]
ffff9e0ce000-ffff9e0f0000 rw-p 00000000 00:00 0 
ffff9e0f0000-ffff9e277000 r-xp 00000000 fe:01 319964                     /usr/lib/aarch64-linux-gnu/libc.so.6
ffff9e277000-ffff9e28c000 ---p 00187000 fe:01 319964                     /usr/lib/aarch64-linux-gnu/libc.so.6
ffff9e28c000-ffff9e290000 r--p 0018c000 fe:01 319964                     /usr/lib/aarch64-linux-gnu/libc.so.6
ffff9e290000-ffff9e292000 rw-p 00190000 fe:01 319964                     /usr/lib/aarch64-linux-gnu/libc.so.6
ffff9e292000-ffff9e29f000 rw-p 00000000 00:00 0 
ffff9e2aa000-ffff9e2d0000 r-xp 00000000 fe:01 319946                     /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
ffff9e2db000-ffff9e2dd000 rw-p 00000000 00:00 0 
ffff9e2e3000-ffff9e2e5000 rw-p 00000000 00:00 0 
ffff9e2e5000-ffff9e2e7000 r--p 00000000 00:00 0                          [vvar]
ffff9e2e7000-ffff9e2e8000 r-xp 00000000 00:00 0                          [vdso]
ffff9e2e8000-ffff9e2ea000 r--p 0002e000 fe:01 319946                     /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
ffff9e2ea000-ffff9e2ec000 rw-p 00030000 fe:01 319946                     /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
ffffdaf66000-ffffdaf87000 rw-p 00000000 00:00 0                          [stack]
```

This tells us which regions of memory are mapped to which files (as well as some other locations like the stack). By replacing `self` in the path with the PID of our child process, we can see the mapping for our child. For our purposes, what we care about are the first and second numbers which represent the location in memory that particular mapping lives at, and the final component which is (at least for the shared objects we care about) the path of the underlying file[^path-ambiguity].

Let's define some structs to help us with this:

```rust
pub struct Region {
    pub start: u64,
    pub end: u64,
    path: String,
}

pub struct MemoryMap {
    pub files: Vec<Region>,
}
```

This post is getting long as it is, so we'll skip the details of those. They're in the git repo in `map.rs` if you want to look at them in more detail. The important part is that `MemoryMap` exposes a function `lookup<'a>(&'a self, addr: u64) -> Option<&'a str>` which will let us move from a program counter location to a path, if it's in our mapping.

We can create the map when the child gets `exec`ed into, and then pass it to our syscall handler:

```rust
pub fn execute(...) {
    ...
    let mut memory_map = MemoryMap::from_pid(child_id);

    println!("Starting to watch child...");
    loop {
        ...
        WaitStatus::PtraceSyscall(pid) => {
            handle_syscall(pid, config, &mut memory_map);
        }
    }
```

We're passing it in as mutable because if we see a syscall that might modify the process memory we'll want to rebuild the map[^rebuild]. Let's handle that part first:

```rust
fn handle_syscall(pid: Pid, config: &Config, map: &mut MemoryMap) {
    let regs = getregs(pid).expect("Could not get registers");
    let syscall = Sysno::from(regs.regs[8] as u32);

    // I don't have an exhaustive knowledge of which syscalls might affect memory.
    // For a real project I'd do more research or set up some tests to see if I'd missed any.
    if BTreeSet::from([
        Sysno::execve,
        Sysno::execveat,
        Sysno::clone,
        Sysno::mmap,
        Sysno::munmap,
        Sysno::mremap,
    ])
    .contains(&syscall)
    {
        *map = MemoryMap::from_pid(pid);
    }

    for addr in [regs.pc, regs.regs[30]] {
        if let Some(loc) = map.lookup(addr) {
            println!("{syscall} from {addr:x} in {loc}");
        }
    }
    
    let mut frame_pointer: u64 = regs.regs[29];
    let mut saved_lr;
    loop {
        if frame_pointer == 0 {
            break;
        }

        saved_lr =
            read(pid, (frame_pointer + 8) as AddressType).expect("failed to read saved lr") as u64;

        if let Some(loc) = map.lookup(saved_lr) {
            println!("{syscall} from {saved_lr:x} in {loc}");
        }

        frame_pointer =
            read(pid, frame_pointer as AddressType).expect("failed to read frame pointer") as u64;
    }

    println!("Reached bottom of stack.");
}
```

Finally we have all the information we need!

## Blocking syscalls

The final piece we need is to walk up the stack until we see a shared object we recognize that has a matching allow or deny rule for the current syscall, or we hit the base. We'll modify `Config` to handle this:

```rust
pub enum Check {
    Allowed,
    Blocked,
    Unknown,
}

impl Config {
    pub fn check(&self, loc: &str, syscall: Sysno) -> Check {
        match self.shared_objects.get(loc) {
            Some(entry) => {
                if entry
                    .allow
                    .as_ref()
                    .is_some_and(|allowed| allowed.contains(&syscall))
                {
                    return Check::Allowed;
                } else if entry
                    .block
                    .as_ref()
                    .is_some_and(|blocked| blocked.contains(&syscall))
                {
                    return Check::Blocked;
                } else {
                    return Check::Unknown;
                }
            }
            None => Check::Unknown,
        }
    }
}
```

Putting everything together, our `handle_syscall` function now looks like this:

```rust
fn handle_syscall(pid: Pid, config: &Config, map: &mut MemoryMap) -> Option<ChildExit> {
    let regs = getregs(pid).expect("Could not get registers");
    let syscall = Sysno::from(regs.regs[8] as u32);

    // I don't have an exhaustive knowledge of which syscalls might affect memory.
    // For a real project I'd do more research or set up some tests to see if I'd missed any.
    if BTreeSet::from([
        Sysno::execve,
        Sysno::execveat,
        Sysno::clone,
        Sysno::mmap,
        Sysno::munmap,
        Sysno::mremap,
    ])
    .contains(&syscall)
    {
        *map = MemoryMap::from_pid(pid);
    }

    for addr in [regs.pc, regs.regs[30]] {
        if let Some(loc) = map.lookup(addr) {
            match config.check(loc, syscall) {
                Check::Allowed => return None,
                Check::Blocked => return Some(ChildExit::IllegalSyscall(syscall, loc.to_string())),
                Check::Unknown => {}
            }
        }
    }

    let mut frame_pointer: u64 = regs.regs[29];
    let mut saved_lr;
    loop {
        if frame_pointer == 0 {
            break;
        }

        saved_lr =
            read(pid, (frame_pointer + 8) as AddressType).expect("failed to read saved lr") as u64;

        if let Some(loc) = map.lookup(saved_lr) {
            match config.check(loc, syscall) {
                Check::Allowed => return None,
                Check::Blocked => return Some(ChildExit::IllegalSyscall(syscall, loc.to_string())),
                Check::Unknown => {}
            }
        }

        frame_pointer =
            read(pid, frame_pointer as AddressType).expect("failed to read frame pointer") as u64;
    }

    return None;
}
```

And if we run the tests we can see that with no restrictions both messages get printed and the child exits 0, but when we restrict the `write` syscall coming from `libprintf_wrapper.so` we only see the "Hello from printf!" before the child process gets terminated! Fantastic!

```sh
$ ./target/debug/crabtrap /usr/local/bin/dynamic config.yaml
Continuing execution in parent process, new child has pid: 11
Starting to watch child...
Hello from printf!
IllegalSyscall(write, "/usr/local/lib/libprintf_wrapper.so")
```

This code is at [`walkthrough-3`](https://github.com/ian-fox/crabtrap/releases/tag/walkthrough-3).

## Next steps

We've shown that the concept works. I think there are a few possible directions to go next, all of them exciting:

* Properly implement the signals, grandchildren, a proper command line interface, all the edge cases, etc. and then find a real example for some benchmarking to see exactly how bad the slowdown is with the naive implementation (probably worth doing a bit more research to see if somebody has actually done this before first...)
* Start diving into one of the other implementations (investigate if some userland bookkeeping along with eBPF for the actual enforcement is possible, or a full-on kernel module)
* Start trying to map code units smaller than shared objects for dependencies that are statically compiled into a program
* Try implementing it as part of the python interpreter, with capabilities at the python package level

I'm not sure which I'll tackle first, if you have any thoughts (or have just found this interesting) feel free to drop me an [email](mailto:ian@whatthefox.dev) any time!

---

[^xz]: I looked a bit into how the xz backdoor worked and I'm not 100% sure that something as simple as this would have stopped it. Later on once I have a working sandbox I'll see if I can test that!
[^syscalls]: Whenever any program running on your computer wants to do something like read a file, open a network connection, it has to ask the operating system for permission. It does this by telling the OS what it wants to do, and then giving control to the OS. The OS will (after checking things like that the program is allowed to do what it's trying to do) carry out the request, and then return control to the program.
[^shared-object]: One method of calling third party code is to use shared objects. We tell our code that we expect there to be a function with a certain name living in a certain shared object file, and then that file will be loaded into our process memory so that we can call the function. This can (very roughly) tell us where a piece of code came from.
[^arm]: This is both because I'm on an ARM laptop, and because I've dealt with x86 assembly and calling conventions before but never ARM. This seemed as good a time as any to jump in!
[^redirects]: Originally I was using `process::Command`, which would have given me this for free. Unfortunately it seems like somewhere inside `process::Command` is an extra call to `clone` that I couldn't quite track, so we're going to roll our own for now. In a real application we'd maybe try to do some more debugging on that to get the nicer interface.
[^signals]: The main one is signal handling. It seems like signals can be tricky with `ptrace`, and while I'm sure it's possible to handle nicely (debuggers must have some way of dealing with it) it's not particularly relevant to the concept we want to prove here.
[^c-quality]: I've never written production C code before. I'm sure there are all sorts of best practices that this isn't following.
[^forking]: Clone is probably better practice, but this is a toy example for now and I like the word fork.
[^first-try]: Not even close, but I've spared you all the silly mistakes.
[^enter-exit]: From the [`ptrace` man page](https://man7.org/linux/man-pages/man2/ptrace.2.html): "Syscall-enter-stop and syscall-exit-stop are indistinguishable from each other by the tracer. The tracer needs to keep track of the sequence of ptrace-stops in order to not misinterpret syscall-enter-stop as syscall-exit-stop or vice versa. In general, a syscall-enter-stop is always followed by syscall-exit-stop, PTRACE_EVENT stop, or the tracee's death; no other kinds of ptrace-stop can occur in between. However, note that seccomp stops (see below) can cause syscall-exit-stops, without preceding syscall-entry-stops. If seccomp is in use, care needs to be taken not to misinterpret such stops as syscall-entry-stops."
[^pc]: "program counter" - this is like a bookmark telling the child process what step of its instructions it's currently executing. It's how we'll be able to tell which piece of code is trying to make the syscall.
[^verify-previous-pc]: Just to verify, we can also check that the previous pc from `r30` is the same as the link register when we go down one frame on the stack.
[^path-ambiguity]: As the doc points out, the pathname is potentially ambiguous when newlines are present or the underlying file has been deleted. I'm sure we could disambiguate this by looking at the inode instead, but that's beyond the scope of this proof of concept.
[^rebuild] Unfortunately, because the "files" in the `/proc/` filesystem aren't actually files, we can't just subscribe to get notified and rebuild the map any time it changes.

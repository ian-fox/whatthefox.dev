+++
title = "Crabtrap Part 2: Electric Boogaloo"
date = "2024-07-05T18:57:45+02:00" 

[taxonomies]
tags = ["computers", "linux", "crabtrap"]
categories = ["blog"]
+++

[Last time](@/posts/crabtrap/index.md) we built a proof-of-concept of a tool which could run a process in linux with guardrails around syscalls based on what shared object they originated from. This time we'll fill in some of the missing functionality to be able to run more programs.

<!-- more -->

## Signals and grandchildren

One of the corners we cut last time was assuming that our child process would never get any signals, and that it would never fork or clone itself so we only had one child to worry about. It turns out both of these were actually pretty easy to fix! As before we'll start with a really simple toy example that does some waiting and some fork/execing:

{% message(title="child.c") %}
```c,linenos
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

void make_child(int i) {
    if (i == 0) {
        return;
    }

    pid_t p = fork();
    if (p < 0) {
        perror("fork failed");
        exit(1);
    }

    if (p == 0) {
        make_child(i - 1);
        sleep(i);
        switch (i) {
            case 3: printf("Child %d calling static...\n", i);
                if (execv("/usr/local/bin/static", NULL) == -1) {
                    perror("execv failed");
                    exit(1);
                }
            case 2: printf("Child %d calling dynamic...\n", i);
                if (execv("/usr/local/bin/dynamic", NULL) == -1) {
                    perror("execv failed");
                    exit(1);
                }
            case 1: printf("Child %d calling all-in-one...\n", i);
                if (execv("/usr/local/bin/all-in-one", NULL) == -1) {
                    perror("execv failed");
                    exit(1);
                }
        }
    } else {
        waitpid(p, NULL, 0);
        printf("Goodbye from parent %d!\n", i);
    }
}

int main() {
    make_child(3);
}
```
{% end %}

This program will give us the following output, and will use some signals and forking while doing it:

{% shell(command="/usr/local/bin/child", dialect="sh") %}
Child 1 calling all-in-one...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 1!
Child 2 calling dynamic...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 2!
Child 3 calling static...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 3!
{% end %}

Excellent! Let's see what happens if we try to run it from `crabtrap`:

{% shell(command="cargo run /usr/local/bin/child", dialect="sh") %}
Continuing execution in parent process, new child has pid: 217
Starting to watch child...
Child 1 calling all-in-one...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 1!
Child 2 calling dynamic...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 2!
Child 3 calling static...
Hello from printf!
Hello from printf_wrapper!
thread 'main' panicked at src/lib.rs:117:23:
unexpected child process status Stopped(Pid(217), SIGCHLD)
{% end %}

That's actually a lot farther than I thought it'd get! In the previous post we assumed that no signals or forks would happen in the child, but we didn't actually validate that. Let that be a lesson to us.

Let's start by handling that unexpected child process. We'll move the `syscall` function that restarts the child to only come after an actual `PtraceSyscall` event, and add an arm for stopped children that tells us something is happening, but doesn't restart them:

```rust
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    println!("Starting to watch child...");
    syscall(child, None).expect("failed to start child");

    loop {
        match waitpid(child, None).expect("failed to get status from waitpid") {
            WaitStatus::Exited(_, code) => {
                return ChildExit::Exited(code);
            }
            WaitStatus::PtraceSyscall(pid) => {
                if let Some(exit) = handle_syscall(pid, config, &mut memory_map) {
                    kill(pid).expect("failed to kill child");
                    return exit;
                }
                syscall(pid, None).expect("failed to restart child");
            }
            WaitStatus::Stopped(pid, signal) => {
                println!("Child {pid} stopped: {signal}");
            }
            status => panic!("unexpected child process status {status:?}"),
        }
    }
```

At this point the process doesn't panic any more, but it does hang on that `SIGCHLD`. This is because the child didn't actually receive the signal! If we go back to our handy [manual](https://man7.org/linux/man-pages/man2/ptrace.2.html), we'll read the following:

> When a (possibly multithreaded) process receives any signal
> except SIGKILL, the kernel selects an arbitrary thread which
> handles the signal.
> ...
> If the selected thread is traced, it enters signal-delivery-stop.
> At this point, the signal is not yet delivered to the process,
> and can be suppressed by the tracer.  If the tracer doesn't
> suppress the signal, it passes the signal to the tracee in the
> next ptrace restart operation.  This second step of signal
> delivery is called signal injection...

...

> After signal-delivery-stop is observed by the tracer, the tracer
> should restart the tracee with the call
>
>        ptrace(PTRACE_restart, pid, 0, sig)

There are a few notes on making sure you're catching the right signal, but it seems like the rust `ptrace` library is handling that for us. The result is that when we observe this stopped state, we actually need to pass the signal through to the child like so:

```rust
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    loop {
        match waitpid(child, None).expect("failed to get status from waitpid") {
            ...
            WaitStatus::Stopped(pid, signal) => {
                syscall(pid, signal)
                    .unwrap_or_else(|e| panic!("failed to restart child after event {pid}: {e}"));
            }
```

At this point the child program does actually run! If we try to run it with our config to block `libprintf_wrapper` though, we find that it fails to block the banned syscalls. This is because while we've dealt with the signal delivery, we're actually missing a large portion of the picture: we're still only tracing our immediate child!

## Tracing multiple children

Right now we're tracing our immediate child, but as soon as that child does a `fork`[^fork] the grandchildren are just running free. We need to start by telling `ptrace` that we want it to start tracing any new processes or threads our child creates. We can do this by changing what options we set on `ptrace` way back before we even start our child:

```rust
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    setoptions(
        child,
        Options::PTRACE_O_EXITKILL
            .union(Options::PTRACE_O_TRACESYSGOOD)
            .union(Options::PTRACE_O_TRACEFORK)
            .union(Options::PTRACE_O_TRACECLONE)
            .union(Options::PTRACE_O_TRACEVFORK)
            .union(Options::PTRACE_O_TRACEEXEC),
    )
    .expect("failed to set ptrace options");
```

Before we had set `EXITKILL`, which would kill our descendants if we exited, and `TRACESYSGOOD`, which is used to distinguish signal delivery stops from syscall stops[^sysgood]. The new ones we've added tell ptrace that any time a tracee calls `execve` we want it to deliver us an event[^trace-exec], and that if a tracee `fork`, `clone`, or `vfork` we want it to start tracing the newly created process as well. This also means we have some new events to handle in our loop.

Part of these settings is that ptrace will send a `SIGSTOP` to the newly created process, so if we see a `fork`, `clone`, or `vfork` happen we'll want to retrieve the new child's pid with `getevent` and make a note that next time we would inject a `SIGSTOP` to it, we should ignore it:

```rust
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    let mut ignore_next_stop: BTreeSet<Pid> = BTreeSet::new();

    println!("Starting to watch child...");
    syscall(child, None).expect("failed to start child");
    loop {
        match waitpid(child, None).expect("failed to get status from waitpid") {
            ...
            WaitStatus::Stopped(pid, signal) => {
                if signal == Signal::SIGSTOP && ignore_next_stop.contains(&pid) {
                    ignore_next_stop.remove(&pid);
                    syscall(pid, None).unwrap_or_else(|e| {
                        panic!(
                            "failed to restart child {pid} after suppressing SIGSTOP: {e}"
                        )
                    });
                    continue;
                }

                syscall(pid, signal).unwrap_or_else(|e| {
                    panic!("failed to restart child {pid} after signal {signal}: {e}")
                });
            }
            WaitStatus::PtraceEvent(pid, _, event)
                if event == Event::PTRACE_EVENT_EXEC as c_int =>
            {
                syscall(pid, None).unwrap_or_else(|e| {
                    panic!(
                        "failed to restart child {pid} after EVENT_EXEC: {e}",
                        event_from_int(event)
                    );
                });
            }
            WaitStatus::PtraceEvent(pid, _, event)
                if event == Event::PTRACE_EVENT_FORK as c_int
                    || event == Event::PTRACE_EVENT_VFORK as c_int
                    || event == Event::PTRACE_EVENT_CLONE as c_int =>
            {
                let new_child_pid = Pid::from_raw(
                    getevent(pid)
                        .unwrap_or_else(|e| panic!("failed to get new child of {pid}: {e}"))
                        .try_into()
                        .unwrap(),
                );
                if !ignore_next_stop.insert(new_child_pid) {
                    panic!("new child {new_child_pid} already in list to ignore next SIGSTOP");
                }
                syscall(pid, None).unwrap_or_else(|e| panic!("failed to restart child {pid} after event {event}: {e}"));
            }
```

We also need to modify two other things. Our call to `waitpid` will change to waiting on `None`, which will get us events from all of our descendants instead of only our immediate child. And naturally, if we're getting events from our descendants, not every `WaitStatus::Exited` will mean we actually want to return! If a grandchild process exits we want to keep going.

A simple solution to this is that `waitpid` will fail with `ECHILD` if we have no descendants, so we can modify our exit condition to look for that:

```rust
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    let mut child_exit = None;

    println!("Starting to watch child...");
    syscall(child, None).expect("failed to start child");
    loop {
        match waitpid(None, None) {
            Err(Errno::ECHILD) => { => {
                return ChildExit::Exited(
                    child_exit.unwrap_or_else(|| panic!("unknown exit status for child {child}")),
                )
            }
            Ok(WaitStatus::Exited(pid, code)) => {
                if pid == child {
                    child_exit = Some(code);
                }
            }
            ...
        }
    }
}
```

That was a lot! We can run child programs that use `fork`, `vfork`, and `clone` now[^edge-cases]!

## Juggling memory maps

The final piece of the puzzle (for today at least) is that with multiple tracees we'll need multiple memory maps to keep track of them. Right now if we try to run our example program with the config forbidding `libprintf_wrapper` it _probably_ won't block because we're only keeping track of the memory of one process. Depending on which child was last used to build the memory map, we may block or we may not! We can fix this by having a separate memory map per child[^sharing]:

```rust,linenos
fn parent(child: Pid, config: &Config) -> ChildExit {
    ...
    let mut children: BTreeMap<Pid, Box<MemoryMap>> =
        BTreeMap::from([(child, Box::new(MemoryMap::from_pid(child).unwrap()))]);
    ...

    loop {
        match waitpid(None, None) {
            ...
            Ok(WaitStatus::PtraceSyscall(pid)) => {
                let child_mem: &mut MemoryMap = children
                    .entry(pid)
                    .or_insert(Box::new(MemoryMap::from_pid(pid).unwrap_or_else(|e| {
                        panic!("Couldn't build map for {}: {}", pid, e)
                    })));

                if let Some(exit) = handle_syscall(pid, config, child_mem) {
                    kill(pid).unwrap_or_else(|e| panic!("failed to kill child {pid}: {e}"));
                    return exit;
                }
                syscall(pid, None)
                    .unwrap_or_else(|e| panic!("failed to restart child {pid} after syscall: {e}"));
            }
```

At long last we can see the fruits of our effort! Note that the `printf_wrapper` call from `all-in-one` doesn't get caught, because that was the version where the function was statically compiled into the binary and thus it doesn't load the `libprintf_wrapper.so`. However as soon as we hit one of the other cases...

{% shell(command="cargo run -- --config config.yaml /usr/local/bin/child", dialect="sh") %}
Continuing execution in parent process, new child has pid: 8512
Starting to watch child...
Child 1 calling all-in-one...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 1!
Child 2 calling dynamic...
Hello from printf!
IllegalSyscall(write, "/usr/local/lib/libprintf_wrapper.so")
{% end %}

Bingo! We can even run things interactively, because we're not doing any input or output redirection:

{% shell(command="cargo run -- --config config.yaml /usr/local/bin/sh", dialect="sh") %}
Continuing execution in parent process, new child has pid: 8518
Starting to watch child...
# all-in-one
Hello from printf!
Hello from printf_wrapper!
# child
Child 1 calling all-in-one...
Hello from printf!
Hello from printf_wrapper!
Goodbye from parent 1!
Child 2 calling dynamic...
Hello from printf!
IllegalSyscall(write, "/usr/local/lib/libprintf_wrapper.so")
{% end %}

There are still lots of details we've just sort of brushed over for the proof of concept, but it should be enough to try swapping the filtering layer out for eBPF. Tune in next time when we'll try that!

[^fork]: Or `clone`, or `vfork`.
[^sysgood]: This one we actually need to set for the rust `ptrace` library to work properly, otherwise it will always return `SIGTRAP` events instead of the nice `PtraceSyscall` events.
[^trace-exec]: Useful because otherwise when `execve` is called the tracee would receive a `SIGTRAP`, and we want to distinguish an `exec` from an actual `SIGTRAP` that we need to inject into the child.
[^edge-cases]: As always, ignoring some edge cases around things like proper error handling.
[^sharing]: Just like with many things in this proof of concept, there is probably lots of opportunity here for performance improvements by e.g. using some kind of copy-on-write data structure that would let us reuse the same map for all of the threads that are in the same child process.
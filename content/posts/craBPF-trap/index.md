+++
title = "CraBPF-trap"
date = "2024-06-24T20:38:45+02:00" 

[taxonomies]
tags = ["computers", "linux", "crabtrap"]
categories = ["blog"]
+++

[Last time](@/posts/crabtrap/index.md) we built a proof-of-concept of running a process in linux with some monitoring around syscalls to allow or deny them based on what shared object they originated from. This time, let's have a look at the feasibility of using eBPF instead of `ptrace`.

<!-- more -->

If we were going to use eBPF


https://docs.rs/libbpf-rs/0.23.3/libbpf_rs/
https://man7.org/linux/man-pages/man7/bpf-helpers.7.html
https://www.kernel.org/doc/html/latest/bpf/index.html
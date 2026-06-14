+++
title = "Doc Freshness"
date = "2026-06-14T17:57:25+02:00"

[taxonomies]
tags = ["computers", "development", "tooling", "LLMs"]
categories = ["blog"]

[extra]
sidenotes = true
+++

I've been meaning to write about some ideas related to coding with AI for a while. Initially I set the scope way too large{% sidenote() %}Wanting to publish ready-to-use tools with good docs and everything first, for instance{% end %} and of course that leads to not writing anything.

So I'm going to start by taking a more casual approach and describe some of the ideas at a higher level, in the hope that it will be useful. Maybe at some point I'll build a tool that's robust enough I feel confident releasing and supporting it, but we'll worry about that later.

This is the first post in that (hopefully) series.

<!-- more -->

## Background

I was onboarding to a new codebase recently-ish which had a lot of documentation embedded in markdown files. Usually this is great! Unfortunately large parts of the docs, while maybe accurate when they were first written, hadn't been kept up to date and were _definitely_ inaccurate by the time I was getting started. It was actually worse than not having any docs, because they pointed you in the wrong direction.

I figured this was a good opportunity to put some ideas I'd had for a while into practice and try them out, the first of which was tooling to help keep docs up to date.

Of course, this isn't a problem you can solve with purely better tools; you're always going to need a team that cares enough to spend the effort keeping docs high-quality and up-to-date.{% sidenote() %}And of course there are plenty of projects which maintain a high standard of documentation even without tools like this.{% end %} But my hope is that tooling could make it take less effort to be able to hit that point.

Specifically, my initial goal was to make a tool which would provide hints to a code reviewer (whether that's a human or a LLM){% sidenote() %}More on LLM-related reviews in a future post...{% end %} about which docs describe the files changed in a given changeset so that they can be reviewed to ensure they're still accurate.{% sidenote() %}Of course, you could try a best-effort kind of thing where instead of having it provide feedback to the reviewer you just say "here are the changes, LLM go make the docs reflect them" but I don't trust LLMs nearly enough to just let them do that without a human review yet.{% end %}

## Implementation

The idea is fairly simple: for many pieces of documentation, there are probably some specific places in the codebase which correspond to things that document is describing. If we track those associations we can look at what code files are changed in a git diff and call out all of the docs which might need to be updated.

There are only a handful of components involved, at least with my first prototype:

* A mapping of which docs correspond to which paths on the filesystem
* A script to look at git diffs, check which files are changed, compare that against the mapping, and suggest which docs should be checked
* (Optional) A LLM reviewer which takes the list of files and looks at the diff to see if they're still accurate 

### Mapping

The mapping is pretty simple at this point. It's a yaml file that looks like this:

```yaml
mapping:
  - description: "The FOO package is described by its own README and heavily used in the BAR guide"
    docs:
      - packages/FOO/README.md
      - docs/guides/BAR.md
    code:
      - packages/FOO/**/*.py
```

### Script

The script itself is pretty simple. It does the following:

- Read the list of changed files from `git diff --name-only` and compare them to the files changed in a changeset
- Match the changed files against the doc mapping to see what docs should be checked
- Emit the results

The main part (simplified for brevity):

```python
@dataclass
class MappingEntry:
  description: str     # Explanation of why the mapping is needed
  docs: set[Path]      # Paths to the relevant docs
  code: set[PathSpec]  # Gitignore-style glob expressions for the described code

def print_mapping(doc_map: set[MappingEntry] changed_files: set[Path]) -> None:
  """Given a list of changed paths, suggest what docs should be double-checked for drift."""

  matching_entries: dict[MappingEntry, set[Path]] = defaultdict(set)

  for map_entry in doc_map:
    for path in changed_files:
      if map_entry.code.match_file(path):
        matching_entries[map_entry].add(path)
  
  for entry, changed_files in matching_entries.items():
    print(f"Docs from {entry} should be reviewed because of changes in {changed_files}")
```

### Prompt

The prompt calls two scenarios the reviewer should check for:

- For each of the docs the script found, are they still accurate with respect to the code changes?
- Should we add or update mappings for any moved/newly created files?

## Is this actually useful?

So far this has definitely caught some helpful things I missed, but it has the potential to generate a lot of noise as well and isn't appropriate for all types of documentation.

For instance there are already tools like [sphinx](https://www.sphinx-doc.org/en/master/index.html) or [rustdoc](https://doc.rust-lang.org/rustdoc/index.html) which generate API docs from code. They can pull type signatures and function names straight from the code to generate a more human-friendly doc. This certainly isn't a good fit for that kind of usecase. Even when there are doc-comments which get incorporated into the generated doc, the fact that those comments are located right next to the code means that a normal review should be able to catch when they drift if the reviewer is given instructions to look for that.

At the opposite extreme of scope/abstraction, if you have something like an `ARCHITECTURE.md` at the root of the repo which is supposed to describe the architecture of the entire system, you don't gain much by just mapping it to `*` because that will fire for every single merge request that changes anything.

Somewhere in the middle is where I think the system is most useful right now. Keeping track of things like "this component over in `src/packages/internal/foo` gets used in this doc over in `docs/guides/bar`. If you update the code of foo, it makes sense to check that the guide is still up to date" is the sweet spot where I've found the reminders helpful.

## Possible improvements

There's plenty of room to get fancier with the implementation details, e.g. by adding support for pattern matching ("match all changes in `services/<service>/*` to `services/<service>/README.md`) to reduce the number of entries needed in the map, or being able to map at a finer grain than individual files ("this subsystem is described in this specic subheading of a markdown file, rather than the whole markdown file"). You could even allow for pointing to external URLs to try to keep up with changes made to relevant external tools/libraries.

The thing that I think is most interesting to explore though is if we can modify the basic structure to take advantage of the notion of encapsulation to address the scope problem mentioned above.

## Encapsulation

Encapsulation is an important principle of software design: you have some kind of contract you provide to users (whether that's end users or just components higher up your stack using a lower-level module). As long as that external contract doesn't change, the users outside the module shouldn't need to care how the module is implemented on the inside.

Designing things this way is useful so that humans can reason about the high-level system without having to have all of the implementation details in mind at once, and I think it could be useful here as well as a way to address docs which describe large parts of a codebase at a high level of abstraction.

I'm not sure yet if this would need to be something best implemented as a change to the script itself or just a different way of using it. For instance maybe each module could have a `README.md` documenting its general use, and that doc itself could be one of the sources which gets mapped to higher-level docs like `ARCHITECTURE.md` when parts of it change. More experimentation is definitely needed.

## Conclusion

There's still lots it doesn't do, but I've found the script (which I've named "Doc Freshness") to be at least somewhat useful so far, provided you keep the mappings specific enough to not generate too much noise.

Some other things related to AI-assisted coding I'd like to write up in the future:

* Where I've been incorporating (and _not_ incorporating) LLM agents into my coding workflows, and patterns I've found useful for that
* What guardrails I put in place
* Some of the general coding principles which I try to get them to follow (also good to keep in mind for when humans are coding!)

Let me know if any of these sound interesting, or if you have thoughts about how to help make it easier to keep docs up-to-date!

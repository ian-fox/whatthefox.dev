+++
title = "Fast-forwarding Videos with Javascript"
date = "2023-01-23T17:59:13+01:00"

[taxonomies]
tags = ["adhd", "browser", "javascript"]
categories = ["blog"]
+++

Maybe you're like me and you have ADHD, and are allergic to watching videos at normal speed. Maybe you're looking to fast-forward through videos for some other reason. YouTube has options for 0.25x to 2x in increments of 0.25. But sometimes you want to go faster than that, or maybe you want a speed between one of those options. Some sites don't have speed controls at all.

There are probably browser extensions that do this, but it will be more fun to do it ourselves. And if you're paranoid, you don't have to trust a random browser extension!

If you don't care about how this works or how you can explore stuff like this and just want to know what code to copy/paste to get these bookmarklets, [skip to the end here](#final-result-tl-dr).

<!-- more -->

## Manipulating Videos with Javascript

Your browser exposes the content of the webpage you're viewing to javascript code so that the code can make the page do useful things. We can write our own code to take advantage of this!

Normally you can right-click an element on a page and choose something like "inspect" to see it in the web browser's developer tools, which will include an area where you can type javascript and have it execute.

We don't want to have to click on a video in order to speed it up though (and some sites like YouTube will actually override the right-click menu with their own stuff), so we can use the `$` operator to grab an element by its tag name and poke around from the browser's [development tools](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/What_are_browser_developer_tools).

![Some of the attributes on an HTML5 video element](video-attributes.png)

If we look at the element representing a video, we can see that it has a _lot_ of attributes (they keep going well beyond what's in the screenshot). Of particular interest to us are the `playbackRate` and `currentTime` attributes. We can change these by assigning them new values:

![Setting the playbackRate and currentTime from the console](setting-attributes.png)

If we leave a video running and mess around with this, we can confirm that changing `playbackRate` and `currentTime` do what we expect, great! Having to go through this whole process every time we wanted to change something would be a drag though. Fortunately we don't have to!

## Bookmarklets

We can automate this process by putting it in a [bookmarklet](https://en.wikipedia.org/wiki/Bookmarklet). We do that by putting our javascript in a bookmark where the URL would normally go, and it'll run when we click the bookmark. Maybe we could create a browser extension or something with a slightly nicer user interface, but that would also take more effort and I think this method is good enough for my purposes.

If we package our code up into a nice function like this:

```javascript
javascript:(function(speed) {
  let videos = document.getElementsByTagName("video");
  for (let i = 0; i < videos.length; i++) {
    videos[i].playbackRate = speed;
  }
})(2);
```

we can copy/paste this into several bookmark definitions and only change the parameter.

Here we're defining a function which takes one parameter (the desired speed) and then immediately calling that function with the speed we want to set the video to (2) as an argument.

In this case it doesn't really save us much because we'd only be changing the speed in one location (the function only has one line in the body), but I think it helps with readability. If we ever want to come back and mess with this code in the future, having a meaningful variable name like "speed" is nice.

The other thing that changed was that we are now using `document.getElementsByTagName` instead of `$`. The reasoning for this is twofold: one is that (at least in my browser), `$` is not defined in the context that the bookmarklets execute in. If you try to use it, you'll get an error in the console.

This necessitates the change on its own, but as a bonus the new way also deals much better with pages that have multiple videos. When using `$`, we only got the first video element from the page. If there were multiple videos and the one we wanted to control wasn't the first one, our bookmarklet wouldn't do what we wanted! This way will modify all videos on the page, which for my purposes is fine because the others are probably paused or muted anyway.

The following bookmarklet will set the speed of all videos to 3x instead of 2x. Note that all we changed was the argument at the end:

```javascript
javascript:(function(speed) {
  let videos = document.getElementsByTagName("video");
  for (let i = 0; i < videos.length; i++) {
    videos[i].playbackRate = speed;
  }
})(3);
```

## Prompting the User

If you don't want a billion bookmarks clogging up your bookmark bar you could also prompt the user for their desired rate.

```javascript
javascript:(function() {
  let speed = prompt("Enter desired video speed");
  let videos = document.getElementsByTagName("video");
  for (let i = 0; i < videos.length; i++) {
    videos[i].playbackRate = speed;
  }
})();
```

This lets us only have one bookmark, but does mean we need to type in the speed we want each time. I ended up finding that dedicated bookmarks for 1x, 2x, 2.5x, 3x, 3.5x, 4x and 8x were a good range of options for me. I can reset the video to normal speed with 1x if there's a complicated part, use the 2-4x depending how fast the people in the video talk, and use 8x to fast forward when looking for a specific piece.

If you don't enter a valid number the bookmarklet will throw an error, but since we're the only people who will be using this we aren't too worried about that. If you really wanted to you could add some checks and alert the user if they entered something that wasn't valid.

## Final Result (TL;DR)

Copy the following code into a bookmark's URL field to make a button which will set the speed of all videos on a webpage to 2x. Change the number before saving to create one that sets it to a different speed. Maybe make multiple if you want e.g. one button to 2x speed, one to 3x, and one to go back to normal. The world is your oyster!

```javascript
javascript:(function(speed) {
  let videos = document.getElementsByTagName("video");
  for (let i = 0; i < videos.length; i++) {
    videos[i].playbackRate = speed;
  }
})(2);
```

The following works the same, but jumps forward thirty seconds (and setting a negative number makes it jump back):

```javascript
javascript:(function(jump) {
  let videos = document.getElementsByTagName("video");
  for (let i = 0; i < videos.length; i++) {
    videos[i].currentTime += jump;
  }
})(30);
```

## Taking it Further

I haven't yet thought about how to do this in a mobile browser, I'm not sure if bookmarklets work there but even if they did it would probably be a bit unwieldy. If you watch a lot of videos on your phone's browser it might be worth looking into writing a browser extension or something. Generally if I'm watching videos on my phone though it's on an app which has these features already.

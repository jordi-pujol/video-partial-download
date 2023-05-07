# video-partial-download
Download only some parts of a video URL

Version 1.

Download up to four parts and merge them into a single video file.

We must specify start time and stop time of each part.

May enter an URL of Html pages que contain a video,
therefore sometimes this utility will detect the real video URL.

Also this utility proposes a title for the recorded video.

The utility **dialog** shows all the info and allows editing.

We can verify the entered info pressing the **Info** button,
and start downloading when pressing the **Download** button.

Supports downloading **m3u8** multipart videos.

Specifying intervals.

Intervals are composed of two timestamps separated by hyphen, (- sign).

In command line Timestamps may be written as:

1:2:0 (Hours, minutes, seconds)

'1h 2m' (blanks will be discarded)

'2m1h' (ordering doesn't matter)

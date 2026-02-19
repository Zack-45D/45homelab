# Homepage

## YouTube Video
- [Homepage](https://www.youtube.com/watch?v=7hc7mjitgIQ)

## What this page contains
Notes and example files used in the **Homepage** video.

## Notes
This has some added configurations that may not be needed depending on your set up. I'll be including all items from the video. I'll add comments to optional sections

## Homepage Setup Walkthrough

**1) File Structure**

In my set up I have all my containers living in `/home/zack/docker/<container_name>` yours may differ


```bash
zack@hl15-beast:~/docker/homepage$ ls -al
total 20
drwxrwxr-x 3 zack zack 4096 Feb 19 13:09 .
drwxrwxr-x 7 zack zack 4096 Feb 17 14:46 ..
drwxrwxr-x 6 zack zack 4096 Jan 30 10:35 config
-rw-rw-r-- 1 zack zack 1345 Feb 19 13:09 docker-compose.yaml
-rw-rw-r-- 1 zack zack  754 Feb 19 13:06 .env
```
The first file we'll tackle is our .env because our docker-compose.yaml and inturn what's in our config will reference it's contents

```bash

```
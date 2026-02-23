# {{TITLE}}

## YouTube Video
- [45Homelab Termix Video](https://www.youtube.com/watch?v=Jw6vh2eOomo)

---

## What this page contains
Notes, commands, and downloadable example files used in the **Termix** video.

---

## Notes / Walkthrough

### Step 1 — Section Title
Explanation of what happens here.

---

### Step 2 — Section Title
Explanation of what happens here.

---

## Commands

```bash
# example command
docker compose up -d
```

---

## Configuration Example

```yaml
services:
  termix:
    image: bugattiguy527/termix:latest
    container_name: termix
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - termix-data:/app/data
    environment:
      PORT: "8080"

volumes:
  termix-data:
    driver: local
```

---

## Example Images

Place images inside:

```
docs/public/files/<ARTICLE_SLUG>/images/
```

Then reference them like this:

```md
<!-- ![Description of image](/files/<ARTICLE_SLUG>/images/example-1.png) -->
```

Example:

<!-- ![Example Screenshot](/files/<ARTICLE_SLUG>/images/example-1.png) -->

Recommended image naming format:

```
example-1.png
example-2.png
config-overview.png
network-diagram.png
```


---

## Files

### 📂 Browse Files Online
View all files directly on GitHub:
https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO>/tree/main/docs/public/files/<ARTICLE_SLUG>/

### ⬇ Download All Files (ZIP)
Download everything in one archive:
`/files/<ARTICLE_SLUG>/<ARTICLE_SLUG>-files.zip`

### Individual Files
- `/files/<ARTICLE_SLUG>/docker-compose.yml`
- `/files/<ARTICLE_SLUG>/example-config.yml`

> All downloadable files for this article are stored in:
>
> `docs/public/files/<ARTICLE_SLUG>/`
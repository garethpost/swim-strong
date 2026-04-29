# Git Push Command

Run this in Terminal after every set of changes to push to GitHub and update the beta site:

```bash
cd ~/Documents/GitHub/swim-strong && rm -f .git/HEAD.lock .git/index.lock .git/objects/maintenance.lock && git add -A && git commit -m "Update" && git push origin main
```

Change the commit message ("Update") to something descriptive if you like.

After pushing, wait ~60 seconds then refresh: https://garethpost.github.io/swim-strong/

# Fork and Sync with Upstream

How to fork the main repository and keep your fork up to date.

## 1. Fork

On GitHub, open `https://github.com/UnpredictablePrashant/StreamingApp` and click
**Fork** to create a copy under your account.

## 2. Clone your fork and add upstream

```bash
git clone https://github.com/<your-username>/StreamingApp.git
cd StreamingApp
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git
git remote -v
```

## 3. Sync updates from upstream

```bash
git fetch upstream
git checkout main
git merge upstream/main      # or: git rebase upstream/main
git push origin main
```

Alternatively, use the **Sync fork** button on the GitHub fork page, or the CLI:

```bash
gh repo sync <your-username>/StreamingApp --source UnpredictablePrashant/StreamingApp
```

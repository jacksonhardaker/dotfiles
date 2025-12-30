# Git Worktree Workflow Helper

This toolkit provides a set of Zsh functions to manage Git worktrees using a Control Repo pattern. It automates the creation, navigation, and cleanup of worktrees, ensuring that branch-specific environments are isolated and easy to manage.

## 📂 Directory Structure

The tooling is designed around a "Container" directory model. It expects a central repository (the Control Repo) to exist within a folder, with worktrees living as siblings to that repository.

Branch names with slashes (e.g., feature/login) are automatically sanitized into hyphenated directory names (e.g., feature-login).

Visual Representation

```
my-repo/                   # Container Directory
├── my-repo.git/           # Control Repo (The main clone)
├── main/                  # Pristine instance of main branch
├── feature-ui-update/     # Worktree for 'feature/ui-update'
├── bugfix-api-error/      # Worktree for 'bugfix/api-error'
└── debug-origin-main/     # Detached worktree for 'origin/main'
```

## 🚀 Installation

1. Copy the Zsh functions into your ~/.zshrc or a dedicated shell script.
2. Source your configuration:

```zsh
source ~/.zshrc
```


### Dependencies

* Git: Core requirement.
* fzf: Required for interactive selection when removing worktrees.
* gh (GitHub CLI): Required for the fpr command to list and checkout Pull Requests.

## 🛠 Command Reference

wt (Main Helper)

The `wt` command is the primary entry point for the workflow.

| Command | Usage | Description |
| - | - | - |
| Checkout | `wt co <branch>` | Navigates to an existing worktree. If it doesn't exist, it creates one. It automatically tracks remote branches if found. |
| New | `wt new <branch> [base]` | Creates a new branch from a specified base (defaults to `main` or `HEAD`) in a new worktree. |
| Debug | `wt debug <remote-branch>` | Creates a detached worktree from a remote branch. Useful for code reviews or debugging without affecting local branches. |
| List | `wt list` | Displays all active worktrees associated with the control repo. |
| Remove | `wt remove [target]` | Removes a worktree. If no target is provided, it opens an `fzf` menu to select one. |
| Prune | `wt prune` | Cleans up stale worktree metadata for directories that were deleted manually. |
| Update | `wt update` | Performs a `fetch --all --prune` and a `pull --ff-only` in the current worktree. |
| Find PR | `wt fpr` | Select a PR to automatically create/switch to a worktree for that PR's branch using `wt co`. |

## ⚙️ Configuration

The script uses a default configuration for the worktree location:

```zsh
: ${WT_DIR:=".."}
```


By default, worktrees are created as siblings to the control repo folder (..). If you wish to store worktrees in a specific subdirectory within your project folder, you can export a different WT_DIR in your shell profile.

## 💡 Key Features

* Automatic Sanitization: Converts path/to/branch into path-to-branch for filesystem compatibility.
* Context Awareness: Commands work whether you are inside the control repo, inside a worktree, or in the parent container directory.
* Safe Debugging: The debug command ensures you don't accidentally commit to a branch you are simply inspecting by using the --detach flag.

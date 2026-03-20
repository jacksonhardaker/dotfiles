
: ${WT_DIR:=".."}  # relative to control repo dir (e.g. bdfe/bdfe.git)

_wt_control_repo() {
  # If we're inside any worktree, resolve the common git dir and map it back to the control repo folder.
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null) || common=""
  if [[ -n "$common" ]]; then
    # common may be ".git" (main worktree) or "/path/to/bdfe.git/.git" (linked worktrees)
    if [[ "$common" == ".git" ]]; then
      local top
      top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
      # if this is the control repo itself, return it; otherwise try to locate a sibling *.git in the container
      if [[ -d "$top/.git" ]]; then
        echo "$top"
        return 0
      fi
    else
      # strip trailing "/.git"
      echo "${common%/.git}"
      return 0
    fi
  fi

  # Not in a git repo: look for a control repo directory here (bdfe.git)
  local gitdir
  gitdir=$(ls -d *.git 2>/dev/null | head -n1)
  if [[ -n "$gitdir" ]]; then
    if [[ -d "$gitdir/.git" || ( -f "$gitdir/HEAD" && -d "$gitdir/refs" ) ]]; then
      echo "$(pwd)/$gitdir"
      return 0
    fi
  fi

  # Or one level down (if you're at a higher container)
  gitdir=$(ls -d */*.git 2>/dev/null | head -n1)
  if [[ -n "$gitdir" ]]; then
    if [[ -d "$gitdir/.git" || ( -f "$gitdir/HEAD" && -d "$gitdir/refs" ) ]]; then
      echo "$(pwd)/$gitdir"
      return 0
    fi
  fi

  return 1
}

_wt_git() {
  local repo
  repo="$(_wt_control_repo)" || {
    echo "wt: could not locate control repo" >&2
    return 1
  }
  git -C "$repo" "$@"
}

_wt_repo_root() {
  _wt_control_repo || {
    echo "wt: could not locate control repo" >&2
    return 1
  }
}

_wt_sanitize() {
  echo "$1" | sed 's#/#-#g'
}

_wt_path_for() {
  local root="$1"
  local ref="$2"
  # Get the parent directory of the control repo (e.g., bdfe/ from bdfe/bdfe.git)
  local container="${root:h}"
  echo "${container}/$(_wt_sanitize "$ref")"
}

_wt_ensure_repo() {
  _wt_control_repo >/dev/null || {
    echo "wt: not in a repo or repo container" >&2
    return 1
  }
}

_wt_usage() {
  cat <<'EOF'
wt - git worktree workflow helper

Usage:
  wt init <url> [dir]             bare-clone <url> and cd into a "main" worktree
  wt co <branch>                  cd to (or create) a worktree for <branch>
  wt new <branch> [base]          create a new branch worktree from [base]
  wt debug <remote-branch>        detached worktree from origin/<remote-branch> (safe)
  wt list                         list worktrees
  wt remove <branch-or-path>      remove a worktree by branch label or path
  wt prune                        prune stale worktree metadata
  wt update                       fetch + pull --ff-only in current worktree

Notes:
  Worktrees live as siblings to the control repo i.e.
  root/
    bdfe.git/          <- control repo (bare clone)
    main/             <- worktree for "main" (created by init)
    feature-foo/      <- worktree for branch "feature/foo"
    bugfix-bar/       <- worktree for branch "bugfix/bar"

  Branch names like feature/foo become directories like feature-foo.
EOF
}

wt() {
  local cmd="${1:-}"
  (( $# )) && shift

  case "$cmd" in
    ""|-h|--help|help)
      _wt_usage
      return 0
      ;;

    init)
      local url="$1"
      local dir="$2"

      if [[ -z "$url" ]]; then
        echo "wt init: missing <url>" >&2
        echo "Usage: wt init <url> [dir]" >&2
        return 1
      fi

      # Derive directory name from URL if not provided
      # e.g. git@github.com:org/my-repo.git -> my-repo
      if [[ -z "$dir" ]]; then
        dir=$(basename "$url" .git)
      fi

      local container="$(pwd)/$dir"
      local bare_dir="${container}/${dir}.git"

      if [[ -d "$bare_dir" ]]; then
        echo "wt init: $bare_dir already exists" >&2
        return 1
      fi

      mkdir -p "$container" || return 1
      echo "Cloning (bare) into ${bare_dir}..."
      git clone --bare "$url" "$bare_dir" || return 1

      # Configure the bare repo to fetch all remote branches
      git -C "$bare_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || return 1
      git -C "$bare_dir" fetch --all --prune || return 1

      # Determine the default branch
      local default_branch
      default_branch=$(git -C "$bare_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
      if [[ -z "$default_branch" ]]; then
        default_branch="main"
      fi

      # Create a worktree for the default branch
      local wtpath="${container}/${default_branch}"
      git -C "$bare_dir" worktree add "$wtpath" "$default_branch" || return 1

      cd "$wtpath" || return 1
      echo "Ready. Control repo: $bare_dir"
      echo "Worktree: $wtpath"
      ;;

    co)
      _wt_ensure_repo || return 1
      local ref="$1"
      if [[ -z "$ref" ]]; then
        echo "wt co: missing <branch>" >&2
        return 1
      fi

      local root="$(_wt_repo_root)" || return 1
      local wtpath="$(_wt_path_for "$root" "$ref")"

      if [[ -d "$wtpath/.git" || -f "$wtpath/.git" ]]; then
        cd "$wtpath" || return 1
        return 0
      fi

      mkdir -p "${root}/${WT_DIR}" || return 1

      if _wt_git show-ref --verify --quiet "refs/heads/$ref"; then
        _wt_git worktree add "$wtpath" "$ref" || return 1
      else
        _wt_git fetch --all --prune >/dev/null 2>&1
        if _wt_git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
          _wt_git worktree add "$wtpath" -b "$ref" "origin/$ref" || return 1
        else
          _wt_git worktree add "$wtpath" -b "$ref" || return 1
        fi
      fi

      cd "$wtpath" || return 1
      ;;

    new)
      _wt_ensure_repo || return 1
      local branch="$1"
      local base="$2"

      if [[ -z "$branch" ]]; then
        echo "wt new: missing <branch>" >&2
        return 1
      fi

      local root="$(_wt_repo_root)" || return 1
      local wtpath="$(_wt_path_for "$root" "$branch")"
      mkdir -p "${root}/${WT_DIR}" || return 1

      if [[ -z "$base" ]]; then
        _wt_git fetch --all --prune >/dev/null 2>&1
        if _wt_git show-ref --verify --quiet "refs/remotes/origin/main"; then
          base="origin/main"
        elif _wt_git show-ref --verify --quiet "refs/heads/main"; then
          base="main"
        else
          base="HEAD"
        fi
      fi

      _wt_git worktree add "$wtpath" -b "$branch" "$base" || return 1
      cd "$wtpath" || return 1
      ;;

    debug)
      _wt_ensure_repo || return 1
      local remote_ref="$1"
      if [[ -z "$remote_ref" ]]; then
        echo "wt debug: missing <remote-branch> (e.g. jane/foo or origin/jane/foo)" >&2
        return 1
      fi

      local root="$(_wt_repo_root)" || return 1
      local full="$remote_ref"
      [[ "$remote_ref" != origin/* ]] && full="origin/$remote_ref"

      _wt_git fetch --all --prune || return 1

      local label="debug/${full}"
      local wtpath="$(_wt_path_for "$root" "$label")"
      mkdir -p "${root}/${WT_DIR}" || return 1

      if [[ -d "$wtpath/.git" || -f "$wtpath/.git" ]]; then
        cd "$wtpath" || return 1
        return 0
      fi

      _wt_git worktree add --detach "$wtpath" "$full" || return 1
      cd "$wtpath" || return 1
      ;;

    list|ls)
      _wt_ensure_repo || return 1
      _wt_git worktree list
      ;;

    remove|rm)
      _wt_ensure_repo || return 1
      local target="$1"
      if [[ -z "$target" ]]; then
        # Let user select from existing worktrees via fzf
        target=$(_wt_git worktree list | fzf --prompt="Select worktree to remove: " | awk '{print $1}')
        [[ -z "$target" ]] && return 0
        _wt_git worktree remove --force "$target"
        return $?
      fi

      if [[ "$target" == /* || "$target" == ./* || "$target" == ../* ]]; then
        _wt_git worktree remove --force "$target"
        return $?
      fi

      local root="$(_wt_repo_root)" || return 1
      local wtpath="$(_wt_path_for "$root" "$target")"
      _wt_git worktree remove --force "$wtpath"
      ;;

    prune)
      _wt_ensure_repo || return 1
      _wt_git worktree prune
      ;;

    update|up)
      _wt_ensure_repo || return 1
      _wt_git fetch --all --prune &&
        git pull --ff-only
      ;;

    
# Fuzzy search pr list and checkout with wt
fpr)
  local pr_num branch repo
  
  # Find the control repo first so we can run gh from there
  repo="$(_wt_control_repo)" || {
    echo "fpr: could not locate control repo" >&2
    return 1
  }
  
  pr_num=$(cd "$repo" && gh pr list | fzf --preview "gh pr diff --color=always {+1}" | { read first rest; echo $first; })
  [[ -z "$pr_num" ]] && return 0
  
  branch=$(cd "$repo" && gh pr view "$pr_num" --json headRefName -q .headRefName)
  [[ -z "$branch" ]] && { echo "Could not get branch name"; return 1; }
  
  wt co "$branch"
  ;;

    *)
      echo "wt: unknown command '$cmd'" >&2
      _wt_usage >&2
      return 1
      ;;
  esac
}

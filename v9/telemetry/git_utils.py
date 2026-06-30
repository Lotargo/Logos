import subprocess

def get_git_info():
    """Returns a dictionary with current git state information."""
    info = {
        "git_commit_hash": None,
        "git_branch": None,
        "dirty_worktree": False
    }

    try:
        # Get commit hash
        commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL).decode("utf-8").strip()
        info["git_commit_hash"] = commit

        # Get branch
        branch = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], stderr=subprocess.DEVNULL).decode("utf-8").strip()
        info["git_branch"] = branch

        # Check if dirty
        status = subprocess.check_output(["git", "status", "--porcelain"], stderr=subprocess.DEVNULL).decode("utf-8").strip()
        info["dirty_worktree"] = len(status) > 0

    except (subprocess.CalledProcessError, FileNotFoundError):
        # Not a git repo or git not installed
        pass

    return info

if __name__ == "__main__":
    import json
    print(json.dumps(get_git_info(), indent=2))

#!/usr/bin/env python3
"""Create Jira tickets for users listed in a text file."""

import argparse
import os
import sys

import yaml
from dotenv import load_dotenv
from jira import JIRA, JIRAError


def load_config(path: str) -> dict:
    load_dotenv()
    with open(path) as f:
        config = yaml.safe_load(f)
    config.setdefault("auth", {})
    if os.getenv("JIRA_EMAIL"):
        config["auth"]["email"] = os.environ["JIRA_EMAIL"]
    if os.getenv("JIRA_API_TOKEN"):
        config["auth"]["api_token"] = os.environ["JIRA_API_TOKEN"]
    if os.getenv("JIRA_PAT"):
        config["auth"]["pat"] = os.environ["JIRA_PAT"]
    if os.getenv("JIRA_URL"):
        config["jira_url"] = os.environ["JIRA_URL"]
    return config


def load_users(path: str) -> list[dict]:
    """Parse users file. Format per line: email[,display_name]"""
    users = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(",", 1)
            email = parts[0].strip()
            name = parts[1].strip() if len(parts) > 1 else email.split("@")[0]
            users.append({"email": email, "display_name": name})
    return users


def connect(config: dict) -> JIRA:
    auth_cfg = config["auth"]
    kwargs = {"server": config["jira_url"]}
    if "api_token" in auth_cfg:
        kwargs["basic_auth"] = (auth_cfg["email"], auth_cfg["api_token"])
    elif "pat" in auth_cfg:
        kwargs["token_auth"] = auth_cfg["pat"]
    else:
        sys.exit("Config error: auth must contain 'api_token' or 'pat'")
    return JIRA(**kwargs)


def find_user(jira: JIRA, email: str):
    """Search for a Jira user by email. Returns user object or None."""
    try:
        for u in jira.search_users(query=email):
            if getattr(u, "emailAddress", "").lower() == email.lower():
                return u
    except JIRAError:
        pass
    return None


def create_user(jira: JIRA, email: str, display_name: str):
    """Create user (Jira Server/DC). Cloud requires SCIM/Admin API — see docs."""
    username = email.split("@")[0]
    try:
        jira.add_user(username=username, email=email, fullname=display_name)
        return find_user(jira, email)
    except JIRAError as e:
        print(f"  WARN: Cannot create user {email}: {e.text}", file=sys.stderr)
        return None


def get_or_create_user(jira: JIRA, email: str, display_name: str, auto_create: bool):
    user = find_user(jira, email)
    if user:
        return user
    if not auto_create:
        print(f"  SKIP: user {email} not found (create_users=false)")
        return None
    print(f"  Creating user {email}...")
    return create_user(jira, email, display_name)


def build_fields(config: dict, user) -> dict:
    """Build Jira issue fields dict from config, interpolating {user}/{email}."""
    t = config["ticket"]
    fmt = {
        "user": user.displayName,
        "email": getattr(user, "emailAddress", ""),
    }

    fields = {
        "project": {"key": config["project_key"]},
        "issuetype": {"name": t["issue_type"]},
        "summary": t["summary"].format(**fmt),
    }

    if "description" in t:
        fields["description"] = t["description"].format(**fmt)
    if "priority" in t:
        fields["priority"] = {"name": t["priority"]}
    if "labels" in t:
        fields["labels"] = t["labels"]
    if "components" in t:
        fields["components"] = [{"name": c} for c in t["components"]]
    if "fix_versions" in t:
        fields["fixVersions"] = [{"name": v} for v in t["fix_versions"]]
    if "parent" in t:
        fields["parent"] = {"key": t["parent"]}
    if "epic_link" in t:
        fields["customfield_10014"] = t["epic_link"]
    if "due_date" in t:
        fields["duedate"] = t["due_date"]

    for k, v in t.get("custom_fields", {}).items():
        fields[k] = v

    return fields


def transition_issue(jira: JIRA, issue, target_status: str):
    for t in jira.transitions(issue):
        if t["name"].lower() == target_status.lower():
            jira.transition_issue(issue, t["id"])
            return True
    print(f"  WARN: transition '{target_status}' not found for {issue.key}")
    return False


def create_ticket(jira: JIRA, config: dict, user):
    fields = build_fields(config, user)
    issue = jira.create_issue(fields=fields)

    if config.get("assign", True):
        assignee_id = getattr(user, "accountId", None) or getattr(user, "name", None)
        jira.assign_issue(issue, assignee_id)

    target = config["ticket"].get("transition_to")
    if target:
        transition_issue(jira, issue, target)

    return issue


def main():
    ap = argparse.ArgumentParser(description="Bulk-create Jira tickets for users")
    ap.add_argument("-c", "--config", default="config.yaml", help="YAML config file")
    ap.add_argument("-u", "--users", default="users.txt", help="Users file (email[,name] per line)")
    ap.add_argument("--dry-run", action="store_true", help="Preview without making API calls")
    args = ap.parse_args()

    config = load_config(args.config)
    users = load_users(args.users)

    if args.dry_run:
        t = config["ticket"]
        print(f"DRY RUN — {len(users)} ticket(s) | project={config['project_key']} "
              f"type={t['issue_type']} priority={t.get('priority', 'default')}")
        for u in users:
            print(f"  {u['email']} ({u['display_name']}) → \"{t['summary'].format(user=u['display_name'], email=u['email'])}\"")
        return

    jira = connect(config)
    auto_create = config.get("create_users", False)
    ok, skip = 0, 0

    for u in users:
        print(f"[{u['email']}]")
        jira_user = get_or_create_user(jira, u["email"], u["display_name"], auto_create)
        if not jira_user:
            skip += 1
            continue
        issue = create_ticket(jira, config, jira_user)
        print(f"  ✓ {issue.key}: {issue.fields.summary}")
        ok += 1

    print(f"\nDone: {ok} created, {skip} skipped.")


if __name__ == "__main__":
    main()

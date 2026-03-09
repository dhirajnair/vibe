# Jira Bulk Ticket Creator

Create Jira tickets for a list of users from a text file. Supports any issue type, configurable fields, optional user creation, and post-creation status transitions.

## Setup (conda)

```bash
conda create -n jira-tickets python=3.11 -y
conda activate jira-tickets
pip install -r requirements.txt
```

## API Token Scopes

Create a Classic API token at **Settings > API tokens** with these scopes:

| Scope | Required | Purpose |
|---|---|---|
| `read:jira-user` | Yes | Search users by email |
| `read:jira-work` | Yes | Read issue data and transitions |
| `read:account` | Yes | Resolve user profiles |
| `write:jira-work` | Yes | Create issues, assign, transition |
| `manage:servicedesk-customer` | Only if `create_users: true` | Auto-create missing users |

Not needed: `manage:jira-configuration`, `manage:jira-data-provider`, `manage:jira-project`, `manage:jira-webhook`, `read:me`, `read:servicedesk-request`.

## Configuration

1. Create your `.env` from the sample:

```bash
cp .env.sample .env
```

2. Fill in your credentials in `.env`:

```
JIRA_EMAIL=dhiraj.nair@uptimecrew.com
JIRA_API_TOKEN=ATATT3x...
```

3. Copy and edit the config:

```bash
cp config.yaml my-config.yaml
```

4. Set your Jira URL, project key, and ticket fields in `my-config.yaml` (auth is loaded from `.env`).

5. Add users to `users.txt` (one per line: `email[,display_name]`):

```
alice@company.com, Alice Smith
bob@company.com
```

## Usage

```bash
# Dry run — preview tickets without calling Jira
python create_tickets.py -c my-config.yaml -u users.txt --dry-run

# Create tickets
python create_tickets.py -c my-config.yaml -u users.txt
```

## Test

Validate config parsing and dry-run output without a live Jira instance:

```bash
python create_tickets.py -c config.yaml -u users.txt --dry-run
```

Expected output:

```
DRY RUN — 3 ticket(s) | project=PROJ type=Task priority=Medium
  alice@company.com (Alice Smith) → "Onboarding: Alice Smith"
  bob@company.com (Bob Jones) → "Onboarding: Bob Jones"
  charlie@company.com (charlie) → "Onboarding: charlie"
```

To run against a real instance, use a test project and verify:

1. Tickets appear in the correct project with the right fields.
2. Each ticket is assigned to the corresponding user.
3. If `transition_to` is set, tickets move to the target status.

# Jira Bulk Ticket Creator

Create Jira tickets for a list of users from a text file. Supports any issue type, configurable fields, optional user creation, and post-creation status transitions.

## Setup (conda)

```bash
conda create -n jira-tickets python=3.11 -y
conda activate jira-tickets
pip install -r requirements.txt
```

## API Token

Create an API token at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens). This is a plain token (no scopes) — it inherits your account's permissions.

## Configuration

1. Create your `.env` from the sample:

```bash
cp .env.sample .env
```

2. Fill in `.env`:

```
JIRA_URL=https://yourorg.atlassian.net
JIRA_EMAIL=you@company.com
JIRA_API_TOKEN=your-api-token
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

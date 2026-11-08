# Setup guide

Self-hosted GitHub Actions runners for one organization, using [myoung34/github-runner](https://hub.docker.com/r/myoung34/github-runner/).

The image does not use the registration token shown on GitHub's "New self-hosted runner" page. On startup it calls the GitHub API and asks GitHub for a fresh registration token. That call needs a personal access token in `ACCESS_TOKEN`.

## Create the token

Create the token with the GitHub account that owns the organization. For `ORG_NAME`, that account must be an organization owner. A member who can only see runners is not enough.

### Do not paste the runner registration token

On **Organization → Settings → Actions → Runners → New self-hosted runner**, GitHub shows a short-lived registration token in the `./config.sh --url ... --token ...` command. That value is about 29 characters and contains only letters and digits.

Do not put that value in `ACCESS_TOKEN`. The container sends `ACCESS_TOKEN` to the GitHub API as `Authorization: token ...`. A registration token is not an API token, so GitHub returns **401** and the runner exits with `Invalid configuration provided for token`.

A usable token looks like one of these:

| Kind | Prefix | Typical length |
| --- | --- | --- |
| Classic personal access token | `ghp_` | 40 characters or more |
| Fine-grained personal access token | `github_pat_` | about 93 characters |

### Classic token (this is the path that works with this image)

1. Open [Generate new token (classic)](https://github.com/settings/tokens/new). Fine-grained tokens are a separate menu and are described below.
2. Set a note such as `organization runners` and choose an expiration. When the token expires, the existing runners keep working, but a new container cannot register until you replace `ACCESS_TOKEN`.
3. Under scopes, select the parent scope **`admin:org`**.
   Selecting only the child scope **Self-hosted runners** is not enough. That child scope is sent to GitHub as `manage_runners:org`. This image registers runners by calling `POST /orgs/{org}/actions/runners/registration-token`, and GitHub answers that call with `X-Accepted-OAuth-Scopes: admin:org`. A token that only has `manage_runners:org` is a valid login and still gets **403**.
4. Generate the token and copy it once. GitHub will not show it again.
5. If the organization enforces SAML single sign-on, open the token in [the token list](https://github.com/settings/tokens) and choose **Configure SSO → Authorize** next to the organization. An unauthorized SSO token also fails when the container asks for a registration token.

No other classic scope is required for organization registration. Do not add extra scopes "just in case"; this token can administer the organization.

### Fine-grained token

Use this only if you do not want a classic token.

1. Open [Fine-grained personal access tokens](https://github.com/settings/personal-access-tokens/new).
2. Set the resource owner to the organization, not your personal account, when GitHub offers that choice.
3. Repository access can be **All repositories**. Registration is an organization operation; it is not tied to one repository.
4. Under **Organization permissions**, set **Administration** to **Read and write**.
5. Generate the token and copy the `github_pat_...` value.

If a fine-grained token returns 403, the organization permission is missing or the token was not granted to this organization. Switch to a classic token with `admin:org` if the fine-grained token cannot call the registration endpoint.

### Repository runner instead of an organization runner

A single repository uses `RUNNER_SCOPE=repo` and `REPO_URL=https://github.com/<owner>/<repo>`. A classic token then needs the **`repo`** scope. An organization runner does not use `REPO_URL`.

## Configure `.env`

```sh
cp .env.example .env
```

Organization runners:

```ini
ACCESS_TOKEN=ghp_your_token
RUNNER_COUNT=4
RUNNER_NAME_PREFIX=runner
LABELS=docker
RUNNER_SCOPE=org
ORG_NAME=your-org
```

`ORG_NAME` is the URL slug (`https://github.com/your-org`), not the display name and not a full URL. `ACCESS_TOKEN` must be the raw token: no quotes, no spaces, and no `Bearer ` prefix.

`RUNNER_COUNT` is how many containers to generate. They share the organization and the token. Each container gets its own name (`runner-1`, `runner-2`, ...) and its own `runner-data` and `work` directories. `docker-compose.yml` is generated and is not committed.

## Generate and start

Windows, from the project directory:

```bat
gen-compose.cmd
docker compose up -d --remove-orphans
docker compose logs -f github-runner-1
```

macOS or Linux:

```sh
chmod +x gen-compose.sh
./gen-compose.sh
docker compose up -d --remove-orphans
docker compose logs -f github-runner-1
```

Both commands read `.env` and write `docker-compose.yml`. Do not edit the Compose file by hand. Change `.env`, then run the command again.

Registration succeeded when the log prints `Listening for Jobs`.

Docker must already be running. On Docker Desktop for Windows, open a new terminal after installing Docker so `docker` is on `PATH`.

## Use the runners

In a workflow of a repository that belongs to the organization:

```yaml
runs-on: [self-hosted, docker]
```

GitHub picks one of the idle runners that has the `docker` label. The process inside the container is Linux. A job that needs `runs-on: windows` cannot use these containers.

If a public repository never picks up the job, open **Organization → Settings → Actions → Runner groups → Default** and allow public repositories. The default group often limits self-hosted runners to private repositories.

## Stop, restart, and scale

```sh
docker compose stop
docker compose up -d --remove-orphans
```

`docker compose down` removes the containers and keeps `runner-data/`. That directory is the saved registration, so a later start does not register the runner again.

Lower `RUNNER_COUNT`, run `gen-compose` again, then `docker compose up -d --remove-orphans`. The extra containers stop. GitHub still lists those runners until you delete them under **Organization → Settings → Actions → Runners**, because automatic deregistration is disabled on purpose. With deregistration enabled, this image refuses to start when runner data is persisted.

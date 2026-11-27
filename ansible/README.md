# Ansible: configuration of the Drupal application servers

This directory is **Stage 3** of the project. Terraform (`../terraform`) builds the AWS
infrastructure; Ansible configures the Amazon Linux 2023 servers that Terraform creates
so that they run Drupal behind the Application Load Balancer.

Nothing in this directory contacts AWS or any server until you run a playbook yourself.

## What gets configured

| Role | What it does |
|---|---|
| `common` | Checks for Amazon Linux 2023, applies security updates, installs base tools, makes sure the SSM agent and time sync are running |
| `php` | Installs PHP 8.3 + the extensions Drupal needs, tunes PHP and the PHP-FPM pool, auto-restart on crash |
| `apache` | Installs Apache (event MPM + PHP-FPM), Drupal virtual host, proxy-header handling, blocks `install.php` on the web |
| `efs` | Installs the EFS mount helper, mounts the shared file system (TLS), creates the shared Drupal directories |
| `drupal` | Installs Composer, builds the code base from one shared `composer.lock`, fetches DB credentials from Secrets Manager, writes `settings.php`, installs Drupal once with Drush |
| `healthcheck` | Publishes `/healthz` for the load balancer |

## Layout

```
ansible.cfg                  Ansible defaults (inventory, become, no fact caching)
requirements.yml             Ansible collections (amazon.aws, ansible.posix)
requirements.txt             Python packages for the control machine
site.yml                     Full configuration run (all roles)
check_connectivity.yml       Read-only: can Ansible reach the servers?
verify.yml                   Read-only: are the servers healthy after a run?
inventory/aws_ec2.yml        Dynamic inventory (finds servers by Terraform's tags)
inventory/hosts.example.yml  Static example with FAKE instance IDs
inventory/local.yml          For running Ansible on a server itself (see below)
group_vars/all/main.yml      Shared variables (mirror terraform.tfvars)
group_vars/all/local.yml.example   Copy to local.yml (git-ignored) and fill in
group_vars/aws_ssm/main.yml  Systems Manager connection settings
roles/*                      The six roles above
tests/render_templates.yml   Renders all templates locally with dummy values
```

## Connection method: AWS Systems Manager (no SSH)

The Terraform configuration has no SSH rule, no key pair and no public IPs, and gives the
servers the `AmazonSSMManagedInstanceCore` policy. So Ansible uses the
`amazon.aws.aws_ssm` connection plugin, which runs commands through Session Manager.

Requirements on **your machine**:

1. AWS credentials for your own IAM user/role (profile, SSO or environment variables; never in this repo).
   It needs permission to describe EC2 instances, start SSM sessions, and use the bucket below.
2. The AWS CLI and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
3. `ansible-galaxy collection install -r requirements.yml` and `python3 -m pip install -r requirements.txt`.
4. **A private S3 bucket for file transfer.** The plugin needs one and the Terraform
   configuration does not create it. Create one yourself (block all public access) and export its name:

   ```
   export ANSIBLE_AWS_SSM_BUCKET_NAME=<your-private-bucket-name>
   ```

   The plugin should hand the servers short-lived pre-signed URLs, so the servers' IAM role
   should not need S3 permissions. If a run fails with HTTP 403 during file transfer, the role does need
   access to that bucket, which is a decision for the Terraform stage.

### Alternative: run Ansible on the instance

If you would rather not create a bucket: open a Session Manager shell on a server, install
Ansible there (`python3 -m pip install ansible-core`, then
`ansible-galaxy collection install -r requirements.yml`), put this directory on the server
(for example `git clone` of your repository; never put credentials in it), and run
`ansible-playbook -i inventory/local.yml site.yml`. Repeat on each server.

## Variables you must set

Run in `../terraform` and copy the result into `group_vars/all/local.yml`
(start from `local.yml.example`):

```
terraform output -raw efs_file_system_id
```

Everything else in `group_vars/all/main.yml` matches the Terraform defaults
(`drupal-ha`, `dev`, `us-east-1`, `10.0.0.0/16`, port 80). If you change those in
`terraform.tfvars`, change them here and in `inventory/aws_ec2.yml` as well.
Also set `drupal_admin_email` to a real address.

## How secrets are handled

* The database password is created by Terraform and kept in Secrets Manager (`<project>-<env>/db-credentials`).
* Each server copies it **itself**, using its own IAM role (which may read only that one secret) into
  `/etc/drupal/db-credentials.json` (`root:apache`, mode 0640). The value never enters an Ansible
  variable, the controller, the Ansible output or any fact cache.
* `settings.php` contains no password; it reads that file when a request arrives. Re-run
  `ansible-playbook site.yml --tags drupal_credentials` after rotating the secret.
* The Drupal administrator password is **not** set by Ansible: Drush generates a random one that is
  never displayed. Get a one-time sign-in link on a server with
  `sudo runuser -u apache -- /var/www/drupal/vendor/bin/drush --root=/var/www/drupal/web user:login`.
* Anyone with a shell on a server can read the credentials file. That is inherent to running Drupal
  on that server; restrict who may start Session Manager sessions.

## Order of a first run

1. Terraform has been applied by you (this stage never does that).
2. `ansible-inventory --graph` shows the two servers.
3. `ansible-playbook check_connectivity.yml`
4. `ansible-playbook site.yml` (configures one server at a time; the first one also installs Drupal)
5. `ansible-playbook verify.yml`
6. Open `http://<alb_dns_name>/` (`terraform output alb_dns_name`).

The `/healthz` endpoint checks that EFS is mounted, the Drupal code is present and the credentials
file is readable. It does not touch the database, so a short database interruption cannot make
every server unhealthy at once.

Until step 4 finishes, the load balancer reports the servers as unhealthy. That is expected.

## Two Terraform values to review after the first successful run (not changed here)

* `health_check_path`: the current default `/` works, but `"/healthz"` is more reliable because it
  does not depend on Drupal or trusted-host settings.
* `asg_health_check_type`: switch from `"EC2"` to `"ELB"` only after `verify.yml` passes, otherwise the
  Auto Scaling Group may replace servers that Ansible has not configured yet.

New servers created later by Auto Scaling are **not** configured automatically; run `site.yml` again
(it is safe to repeat). Automating that is outside this stage.

## Testing without deploying anything

All of these run on your machine only:

```
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i localhost, site.yml --syntax-check
ansible-playbook -i localhost, check_connectivity.yml --syntax-check
ansible-playbook -i localhost, verify.yml --syntax-check
ansible-playbook -i inventory/hosts.example.yml site.yml --list-tasks
ansible-inventory -i inventory/hosts.example.yml --graph
yamllint .
ansible-lint
ansible-playbook -i localhost, -c local tests/render_templates.yml    # then read /tmp/ansible-template-test/*
```

Never run `site.yml` with `-i inventory/aws_ec2.yml` (the default) until you want real servers configured.

## Not included on purpose

* No CloudWatch agent or other chargeable monitoring (a later stage).
* No HTTPS (the Terraform load balancer only has an HTTP listener).
* No Docker, Kubernetes or CI/CD.

## Things to confirm on the first real run

I could not run these roles against an Amazon Linux 2023 server, so these assumptions are untested:

* The PHP package names (`php8.3-*`) and the `/etc/php.d`, `/etc/php-fpm.d/www.conf` paths.
* Drush's `site:install` using the database from `settings.php` without `--db-url`.
* `awscli-2` being preinstalled (the role installs it if missing).

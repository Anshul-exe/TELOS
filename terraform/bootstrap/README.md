# terraform/bootstrap — Remote state backend

This config provisions the **remote state backend** that every other Terraform
config in this repo depends on:

- **S3 bucket** `telos-tfstate-<random-suffix>` — stores remote state.
  Versioning enabled, default SSE-S3 (AES256) encryption, all public access
  blocked.
- **DynamoDB table** `telos-tf-locks` — state locking, `PAY_PER_REQUEST`
  billing, partition key `LockID` (string).

## Why this is special (read before touching)

This is the one Terraform config that **cannot** use a remote backend — it is the
thing that *creates* the remote backend. It therefore uses a **local backend**
(`terraform.tfstate` on disk in this directory).

Consequences:

1. **Apply this exactly once, up front**, before any other config. It is not part
   of the normal `apply` / `destroy` session cycle described in `plan.md`.
2. **Never `terraform destroy` this alongside the rest of the stack.** The state
   bucket and lock table must outlive every ordinary teardown — destroying them
   orphans the remote state of every other config. Both resources also carry
   `prevent_destroy = true` as a guardrail.
3. Its local state (`terraform.tfstate`) is the source of truth for these two
   resources. Keep it — losing it means Terraform forgets it manages the bucket
   and table (they keep working, but you'd have to re-import to manage them
   again). It is gitignored; do not commit it.

These resources cost essentially nothing while idle (empty S3 bucket +
on-demand DynamoDB), so leaving them up permanently between sessions is expected
and cheap.

## Apply command

Run from this directory:

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Default region is `ap-south-1` (matches the existing cluster). Override with
`-var="region=<other-region>"` if needed — it must match the region the rest of
the stack deploys to.

## After apply

Note the outputs:

```bash
terraform output
```

- `state_bucket_name`
- `lock_table_name`
- `region`

Hand these to the next step — they get wired **manually** into
`terraform/envs/dev/backend.tf`, e.g.:

```hcl
terraform {
  backend "s3" {
    bucket         = "<state_bucket_name>"
    key            = "envs/dev/terraform.tfstate"
    region         = "<region>"
    dynamodb_table = "<lock_table_name>"
    encrypt        = true
  }
}
```

Nothing in this bootstrap config wires itself into another module's backend —
that step is intentionally manual.

#!/usr/bin/env bash
# src/agentic/aws/tools/create-devbot-users.sh
# Provision one `devbot-<person>` IAM user per name: programmatic access only,
# member of the shared group, one access key each, printed once.
#
# Usage: create-devbot-users.sh [--dry-run] [--group <group>] <person>...
#
# The group IS the permission model: members inherit the `devbot-read` managed
# policy and `sts:AssumeRole` on `role/devbot-agent`. Nothing is attached to the
# user itself, so adding or removing a member never touches a policy. Names are
# lowercased because IAM user names are case-sensitive and mixed case would fork
# the convention (`Behzad.F` -> `devbot-behzad.f`).
#
# The secret access key is shown ONCE. The file this writes (mode 600, in the
# current directory) is the only other copy — distribute the rows, delete it.
#
# Needs an identity allowed to iam:GetUser, iam:CreateUser, iam:AddUserToGroup
# and iam:CreateAccessKey — the users created here deliberately cannot.

set -uo pipefail

USAGE='usage: create-devbot-users.sh [--dry-run] [--group <group>] <person>...'

_die() {
  echo "create-devbot-users: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
${USAGE}

Creates devbot-<person> IAM users with programmatic access only, adds each to
the shared group (default: devbot) and issues one access key, printed once.
Names are lowercased; a leading "devbot-" is accepted and not doubled.

  --dry-run   show what would happen, change nothing
  --group     group to join (default: devbot)
EOF
}

GROUP=devbot
DRY_RUN=0
people=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --group)
      [[ -n "${2:-}" ]] || _die "--group needs a value"
      GROUP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do people+=("$1"); shift; done ;;
    -*) _die "unknown option: $1" ;;
    *) people+=("$1"); shift ;;
  esac
done

[[ ${#people[@]} -gt 0 ]] || { usage >&2; _die "no names given"; }

OUT="devbot-credentials-$(date +%Y%m%d-%H%M%S).csv"
created=()
skipped=()
failed=()

# Create the credential file on the first success, so a run that creates nothing
# leaves no empty file behind.
_write_row() {
  if [[ ! -f "${OUT}" ]]; then
    printf 'user,access_key_id,secret_access_key\n' >"${OUT}"
    chmod 600 "${OUT}"
  fi
  printf '%s,%s,%s\n' "$1" "$2" "$3" >>"${OUT}"
}

for raw in "${people[@]}"; do
  person="$(printf '%s' "${raw#devbot-}" | tr '[:upper:]' '[:lower:]')"
  name="devbot-${person}"

  if [[ ! "${name}" =~ ^devbot-[A-Za-z0-9+=,.@_-]+$ ]]; then
    echo "FAIL  ${name} (invalid IAM user name)" >&2
    failed+=("${name}")
    continue
  fi

  if aws iam get-user --user-name "${name}" >/dev/null 2>&1; then
    echo "SKIP  ${name} (already exists)"
    skipped+=("${name}")
    continue
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "PLAN  ${name} (create-user, join ${GROUP}, create-access-key)"
    continue
  fi

  if ! aws iam create-user --user-name "${name}" --tags "Key=owner,Value=${person}" >/dev/null; then
    echo "FAIL  ${name} (create-user)" >&2
    failed+=("${name}")
    continue
  fi

  if ! aws iam add-user-to-group --user-name "${name}" --group-name "${GROUP}"; then
    echo "FAIL  ${name} (add-user-to-group ${GROUP})" >&2
    failed+=("${name}")
    continue
  fi

  key="$(aws iam create-access-key --user-name "${name}" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)" \
    || { echo "FAIL  ${name} (create-access-key)" >&2; failed+=("${name}"); continue; }

  # --output text separates the two fields with a tab.
  read -r AK SK <<<"${key}"
  if [[ -z "${AK}" || -z "${SK}" ]]; then
    echo "FAIL  ${name} (create-access-key returned nothing)" >&2
    failed+=("${name}")
    continue
  fi

  _write_row "${name}" "${AK}" "${SK}"
  created+=("${name}")
  echo "OK    ${name}"
done

echo
printf 'created %d, skipped %d, failed %d\n' \
  "${#created[@]}" "${#skipped[@]}" "${#failed[@]}"

if [[ -f "${OUT}" ]]; then
  echo
  echo "== Credentials — also in ${OUT} (mode 600) =="
  column -s, -t "${OUT}" 2>/dev/null || cat "${OUT}"
  echo
  echo "Give each row to its owner, then delete ${OUT}."
fi

[[ ${#failed[@]} -eq 0 ]]

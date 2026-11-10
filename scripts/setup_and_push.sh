#!/usr/bin/env bash
# Initialise, sign, commit, push and release rambabu-projects-logo.
# Run on macOS from anywhere:  bash ~/Projects/rambabu-projects-logo/scripts/setup_and_push.sh
# Safe to re-run: every step checks whether it is already done.
set -euo pipefail

REPO_NAME="rambabu-projects-logo"
TAG="v1.0.0"
SIGNING_KEY="$HOME/.ssh/id_ed25519_git_signing"
ALLOWED_SIGNERS="$HOME/.config/git/allowed_signers"
EVIDENCE_DIR="$HOME/Projects/${REPO_NAME}-evidence"
TRAILERS=$'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01FxmafuLH1yDyfhVM1nU1vC'

cd "$(cd "$(dirname "$0")/.." && pwd)"
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. Prerequisites ----------
log "Checking tools"
for c in git gh shasum ssh-keygen ssh-add; do
  command -v "$c" >/dev/null 2>&1 || die "'$c' not found. Install with: brew install ${c/shasum/perl}"
done
git --version | awk '{split($3,v,"."); if (v[1]<2 || (v[1]==2 && v[2]<34)) exit 1}' \
  || die "git >= 2.34 required for SSH signing. Run: brew install git"

# ---------- 1. GitHub auth ----------
log "Checking GitHub CLI login"
gh auth status -h github.com >/dev/null 2>&1 || gh auth login -h github.com -p https -w
if ! gh api -i user 2>/dev/null | grep -i '^x-oauth-scopes:' | grep -q 'admin:ssh_signing_key'; then
  log "Granting gh permission to upload an SSH signing key (browser opens once)"
  gh auth refresh -h github.com -s admin:ssh_signing_key
fi
LOGIN="$(gh api user -q .login)"
GH_ID="$(gh api user -q .id)"
GH_NAME="$(gh api user -q '.name // empty')"; GH_NAME="${GH_NAME:-Rambabu}"
EMAIL="${GH_ID}+${LOGIN}@users.noreply.github.com"   # keeps your real email out of public history
echo "GitHub user: $LOGIN  |  commit identity: $GH_NAME <$EMAIL>"

# ---------- 2. SSH signing key ----------
log "Setting up SSH commit signing"
mkdir -p "$HOME/.ssh" "$(dirname "$ALLOWED_SIGNERS")"; chmod 700 "$HOME/.ssh"
if [[ ! -f "$SIGNING_KEY" ]]; then
  echo "Creating signing key $SIGNING_KEY (choose a passphrase when asked)"
  ssh-keygen -t ed25519 -C "$EMAIL git-signing" -f "$SIGNING_KEY"
fi
ssh-add --apple-use-keychain "$SIGNING_KEY" 2>/dev/null || ssh-add "$SIGNING_KEY"
PUB="$(cat "${SIGNING_KEY}.pub")"
KEY_BODY="$(awk '{print $2}' "${SIGNING_KEY}.pub")"
touch "$ALLOWED_SIGNERS"
grep -qF "$KEY_BODY" "$ALLOWED_SIGNERS" || echo "$EMAIL namespaces=\"git\" $PUB" >> "$ALLOWED_SIGNERS"
if ! gh api user/ssh_signing_keys --paginate -q '.[].key' | grep -qF "$KEY_BODY"; then
  gh ssh-key add "${SIGNING_KEY}.pub" --type signing --title "git-signing $(scutil --get ComputerName 2>/dev/null || hostname -s)"
fi

# ---------- 3. Repo init + local config ----------
log "Initialising repository"
[[ -d .git ]] || git init -b main
git config user.name  "$GH_NAME"
git config user.email "$EMAIL"
git config gpg.format ssh
git config user.signingkey "${SIGNING_KEY}.pub"
git config gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
git config commit.gpgsign true
git config tag.gpgsign true

# ---------- 4. Checksums ----------
log "Generating SHA256SUMS"
find original main v1 docs -type f ! -name '.DS_Store' | LC_ALL=C sort | xargs shasum -a 256 > SHA256SUMS
shasum -a 256 -c SHA256SUMS

# ---------- 5. One signed commit per version ----------
commit_if_needed() {  # $1 = subject, $2 = body, rest = paths
  local subject="$1" body="$2"; shift 2
  git add -- "$@"
  if git diff --cached --quiet -- "$@"; then echo "skip (already committed): $subject"; return; fi
  git commit -S -m "$subject" -m "$body" -m "$TRAILERS"
}
log "Creating signed commits"
commit_if_needed "original: add untouched Google Gemini export" \
"Unmodified Gemini output (PNG with visible sparkle) and Gemini-generated HTML badge code.
AI-generated with Google Gemini, directed and selected by Rambabu. Not hand-drawn." \
  .gitattributes .gitignore original

commit_if_needed "v1: add full logo with visible Gemini sparkle inpainted" \
"2400x1792 PNG derived from original/. Only the bottom-right sparkle was replaced
(7,809 px inside x2231-2344, y1623-1736). SynthID invisible watermark remains.
AI-generated with Google Gemini, directed and selected by Rambabu." \
  v1

commit_if_needed "main: add square monogram crop and badge showcase page" \
"1152x1152 crop of v1 plus 512 and 180 px downscales, and index.html with a corrected
icon badge (the Gemini HTML referenced an undefined #brandGrad gradient).
AI-generated with Google Gemini, directed and selected by Rambabu." \
  main

commit_if_needed "docs: add README, ATTRIBUTION, SHA256SUMS and setup script" \
"States authorship accurately: AI-generated with Google Gemini, directed and selected
by Rambabu, created 2026-11-10." \
  README.md ATTRIBUTION.md SHA256SUMS docs scripts

git log --show-signature --oneline -n 4

# ---------- 6. GitHub repo + push ----------
log "Creating / linking GitHub repo $LOGIN/$REPO_NAME"
if ! gh repo view "$LOGIN/$REPO_NAME" >/dev/null 2>&1; then
  gh repo create "$REPO_NAME" --public \
    --description "Rambabu neon-circuit monogram. AI-generated with Google Gemini, directed and selected by Rambabu." \
    --source . --remote origin
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/$REPO_NAME.git"
git push -u origin main

# ---------- 7. Signed tag + release ----------
log "Tagging $TAG and publishing release"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || \
  git tag -s "$TAG" -m "$TAG: Rambabu logo. AI-generated with Google Gemini, directed and selected by Rambabu."
git push origin "$TAG"
NOTES="$(mktemp)"; trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<EOF
**AI-generated with Google Gemini, directed and selected by Rambabu.** Created 2026-11-10. Not hand-drawn.

| Asset | Description |
|---|---|
| rambabu-monogram-1152x1152.png | main: square monogram |
| rambabu-monogram-512x512.png | main: icon size |
| rambabu-logo-full-2400x1792.png | v1: full logo, visible sparkle inpainted |
| Gemini_Generated_Image_p0s47p0s47p0s47p.png | original: untouched Gemini export |
| SHA256SUMS | SHA-256 of every asset (verify: \`shasum -a 256 -c SHA256SUMS\`) |

SynthID invisible watermark remains in all images. Commit: $(git rev-parse HEAD)
EOF
if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --verify-tag \
    --title "$TAG: Rambabu logo (AI-generated with Google Gemini)" \
    --notes-file "$NOTES" \
    main/rambabu-monogram-1152x1152.png \
    main/rambabu-monogram-512x512.png \
    v1/rambabu-logo-full-2400x1792.png \
    original/Gemini_Generated_Image_p0s47p0s47p0s47p.png \
    SHA256SUMS
fi

# ---------- 8. Evidence snapshot (kept OUTSIDE the repo) ----------
log "Saving evidence to $EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR"
{
  echo "Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Repo: https://github.com/$LOGIN/$REPO_NAME"
  echo "Commit (HEAD): $(git rev-parse HEAD)"
  echo "Tag object $TAG: $(git rev-parse "$TAG")"
  echo; echo "== Release (GitHub server timestamps) =="
  gh release view "$TAG" --json url,publishedAt,createdAt,tagName,assets \
    -q '"URL: \(.url)\npublishedAt: \(.publishedAt)\ncreatedAt: \(.createdAt)\n" + ([.assets[] | "\(.name)  \(.size) bytes  \(.digest // "")"] | join("\n"))'
  echo; echo "== Signature verification =="
  git verify-commit HEAD 2>&1; git verify-tag "$TAG" 2>&1
  echo; echo "== SHA256SUMS =="; cat SHA256SUMS
} > "$EVIDENCE_DIR/evidence-$TAG.txt"
gh api "repos/$LOGIN/$REPO_NAME/commits/$(git rev-parse HEAD)" > "$EVIDENCE_DIR/commit-api-$TAG.json"
gh api "repos/$LOGIN/$REPO_NAME/releases/tags/$TAG"            > "$EVIDENCE_DIR/release-api-$TAG.json"
cat "$EVIDENCE_DIR/evidence-$TAG.txt"

log "Done: https://github.com/$LOGIN/$REPO_NAME/releases/tag/$TAG"

Basic use:

```bash
chmod +x gittools-kit.sh

# First run: clone/update GitTools and create config example
./gittools-kit.sh init

# Check loaded config
./gittools-kit.sh show-config

# Full workflow for one authorized target
./gittools-kit.sh all \
  --url https://example.com/.git/ \
  --i-have-authorization
```

Finder mode:

```bash
./gittools-kit.sh finder \
  --input authorized-domains.txt \
  --output found-git.txt \
  --threads 20 \
  --i-have-authorization
```

Dumper + extractor separately:

```bash
./gittools-kit.sh dump \
  --url https://example.com/.git/ \
  --dump-dir ./gittools-work/dumps/example \
  --i-have-authorization

./gittools-kit.sh extract \
  --dump-dir ./gittools-work/dumps/example \
  --out ./gittools-work/extracted/example \
  --i-have-authorization
```

Exporter/report:

```bash
./gittools-kit.sh export \
  --input ./gittools-work/extracted/example \
  --out ./gittools-work/export/example \
  --i-have-authorization

./gittools-kit.sh report \
  --input ./gittools-work/export/example
```

Important config setting to use before real testing:

```bash
ALLOWED_HOST_REGEX="(^|\.)yourcompany\.com$"
```

That prevents accidentally running it on out-of-scope domains. Also note upstream says Dumper is not guaranteed to fully recover a repository, especially where pack files are involved.

[1]: https://github.com/internetwache/GitTools "GitHub - internetwache/GitTools: A repository with 3 tools for pwn'ing websites with .git repositories available · GitHub"

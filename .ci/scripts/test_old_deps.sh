#!/usr/bin/env bash
# this script is run by GitHub Actions in a plain `focal` container; it installs the
# minimal requirements for tox and hands over to the py3-old tox environment.

# Prevent tzdata from asking for user input
export DEBIAN_FRONTEND=noninteractive

set -ex

apt-get update
apt-get install -y \
        python3 python3-dev python3-pip python3-venv pipx \
        libxml2-dev libxslt-dev xmlsec1 zlib1g-dev libjpeg-dev libwebp-dev

export LANG="C.UTF-8"

# Prevent virtualenv from auto-updating pip to an incompatible version
export VIRTUALENV_NO_DOWNLOAD=1

# I'd prefer to use something like this
#   https://github.com/python-poetry/poetry/issues/3527
#   https://github.com/pypa/pip/issues/8085
# rather than this sed script. But that's an Opinion.

# patch the project definitions in-place
# replace all lower bounds with exact bounds
# delete all lines referring to psycopg2 --- so no postgres support
# but make the pyopenssl 17.0, which can work against an
# OpenSSL 1.1 compiled cryptography (as older ones don't compile on Travis).

sed -i-backup \
   -e "s/[~>]=/==/g" \
   -e "/psycopg2/d" \
   -e 's/pyOpenSSL = "==16.0.0"/pyOpenSSL = "==17.0.0"/' \
   -e '/psycopg2/d' \
   -e '/systemd/d' \
   pyproject.toml

pip install --user toml

REMOVE_DEV_DEPENDENCIES="
import toml
with open('pyproject.toml', 'r') as f:
    data = toml.loads(f.read())

from pprint import pprint
pprint(data)

del data['tool']['poetry']['dev-dependencies']

with open('pyproject.toml', 'w') as f:
    data = toml.dump(data, f)
"
python3 -c "$REMOVE_DEV_DEPENDENCIES"

# There are almost certainly going to be dependency conflicts there, so I'm going to
# use plain pip to install rather than poetry.

# Can't pip install with -e. Error message:
# > A "pyproject.toml" file was found, but editable mode currently requires a setup.py based build.
# Needs PEP 660 support in poetry, sigh. See
# https://github.com/python-poetry/poetry/issues/34#issuecomment-1055142428
# So instead, make a virtualenv and install in there.

# At the time of writing, this notes:
#  ERROR: ldap3 2.9.1 has requirement pyasn1>=0.4.6, but you'll have pyasn1 0.1.9 which is incompatible.
# Helpfully, pip doesn't indicate the error; it returns 0.
# TODO: bump pyasn to >=0.4.6?
pipx install poetry==1.1.12
~/.local/bin/poetry lock
~/.local/bin/poetry install -E "all test"
~/.local/bin/poetry run trial -j2 tests
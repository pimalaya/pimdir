#!/bin/sh
# usage: nmconf.sh MAIL_ROOT DB_DIR CONFIG_PATH
cat > "$3" <<CONF
[database]
mail_root=$1
path=$2
[user]
name=Bench
primary_email=bench@example.org
[new]
tags=unread;inbox
ignore=
[search]
exclude_tags=
[maildir]
synchronize_flags=true
CONF

#!/usr/bin/env bash

LANGUAGES=$(cat <<-END
python
go
javascript
nodejs
tmux
typescript
zsh
cpp
c
lua
rust
bash
php
haskell
css
html
END
)

COMMANDS=$(cat <<-END
gdb
find
man
tldr
sed
awk
tr
cp
ls
grep
xargs
rg
ps
mv
kill
lsof
less
head
tail
tar
cp
rm
rename
jq
cat
ssh
cargo
git
git-worktree
git-status
git-commit
git-rebase
docker
docker-compose
stow
chmod
chown
make
END
)

# FZF act's as dmenu, on C-RET we print query instead selection
selected=`echo "$LANGUAGES\n$COMMANDS" | fzf --bind=enter:replace-query+print-query`
if [[ -z $selected ]]; then
    exit 0
fi

read -p "Enter Query (<CR> or <C-CR>): " query

tmux neww bash -c "curl -s cht.sh/$selected~$query|less -R"

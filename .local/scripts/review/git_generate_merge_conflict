# based on [Force a Git Conflict](https://stackoverflow.com/a/53342385/4722574)
# init your repo
git init

# print some text to any given file
echo 'aaa' > a.txt

# commit to the current branch
git add a.txt && git commit -m "Commit1"

# create a new branch
git switch -c branch1

# add code to the end of the file
echo 'bbb' >> a.txt

# commit to the current branch (b)
git add a.txt && git commit -m "Commit2"

# get back to master branch
git switch main

# add code to the end of the file
# here the file will still have its original code
echo 'ccc' >> a.txt

# commit to the current branch (main)
git add a.txt && git commit -m "Commit3"

# now when you will try to merge you will have conflict
git merge branch1
# Design
## Race and ordering
Two writers: the lock directory is taken with mkdir and must be released on every exit path, including a failing put.

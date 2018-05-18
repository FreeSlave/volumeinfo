# Volumeinfo

D library for getting information about mounted volumes (partitions).
The information includes total and free size, filesystem type and display name.

Inspired by QStorageInfo from Qt.

## [Example](examples/list.d)

Print mounted volumes:

    dub examples/list.d

Print volumes where the provided paths reside:

    dub examples/list.d $HOME /usr/share

# Volumeinfo

D library for getting information about mounted volumes (partitions).
The information includes total and free size, filesystem type and display name.

Inspired by QStorageInfo from Qt.

[![Build Status](https://github.com/FreeSlave/volumeinfo/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/FreeSlave/volumeinfo/actions/workflows/ci.yml)
[![Windows Build Status](https://ci.appveyor.com/api/projects/status/github/FreeSlave/volumeinfo?branch=master&svg=true)](https://ci.appveyor.com/project/FreeSlave/volumeinfo)
[![Coverage Status](https://coveralls.io/repos/FreeSlave/volumeinfo/badge.svg?branch=master&service=github)](https://coveralls.io/github/FreeSlave/volumeinfo?branch=master)

[Online documentation](http://freeslave.github.io/volumeinfo/volumeinfo.html)

## Supported platforms

Windows, GNU/Linux and propably FreeBSD (code was written, but was not tested in its current form).

## [Example](examples/list.d)

Print mounted volumes:

    dub examples/list.d

Print volumes where the provided paths reside:

    dub examples/list.d "$HOME" /usr/share

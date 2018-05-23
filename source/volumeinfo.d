/**
 * Getting currently mounted volumes and information about them in crossplatform way.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2018
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module volumeinfo;

import std.typecons : RefCounted, BitFlags;

version(Windows)
{
    import core.sys.windows.windows;
    import std.utf : toUTF16z, toUTF8;
    import core.stdc.wchar_ : wcslen;
}

version(OSX) {} else version(Posix)
{
    private @safe bool isSpecialFileSystem(const(char)[] dir, const(char)[] type)
    {
        import std.string : startsWith;
        if (dir.startsWith("/dev") || dir.startsWith("/proc") || dir.startsWith("/sys") ||
            dir.startsWith("/var/run") || dir.startsWith("/var/lock"))
        {
            return true;
        }

        if (type == "tmpfs" || type == "rootfs" || type == "rpc_pipefs") {
            return true;
        }
        return false;
    }
}

version(FreeBSD)
{
private:
    import core.sys.posix.sys.types;

    enum MFSNAMELEN = 16;          /* length of type name including null */
    enum MNAMELEN  = 88;          /* size of on/from name bufs */
    enum STATFS_VERSION = 0x20030518;      /* current version number */
    enum MNT_RDONLY = 1;

    struct fsid_t
    {
        int[2] val;
    }

    struct statfs_t {
        uint f_version;         /* structure version number */
        uint f_type;            /* type of filesystem */
        ulong f_flags;           /* copy of mount exported flags */
        ulong f_bsize;           /* filesystem fragment size */
        ulong f_iosize;          /* optimal transfer block size */
        ulong f_blocks;          /* total data blocks in filesystem */
        ulong f_bfree;           /* free blocks in filesystem */
        long  f_bavail;          /* free blocks avail to non-superuser */
        ulong f_files;           /* total file nodes in filesystem */
        long  f_ffree;           /* free nodes avail to non-superuser */
        ulong f_syncwrites;      /* count of sync writes since mount */
        ulong f_asyncwrites;         /* count of async writes since mount */
        ulong f_syncreads;       /* count of sync reads since mount */
        ulong f_asyncreads;      /* count of async reads since mount */
        ulong[10] f_spare;       /* unused spare */
        uint f_namemax;         /* maximum filename length */
        uid_t     f_owner;          /* user that mounted the filesystem */
        fsid_t    f_fsid;           /* filesystem id */
        char[80]      f_charspare;      /* spare string space */
        char[MFSNAMELEN] f_fstypename; /* filesystem type name */
        char[MNAMELEN] f_mntfromname;  /* mounted filesystem */
        char[MNAMELEN] f_mntonname;    /* directory on which mounted */
    };

    extern(C) @nogc nothrow
    {
        int getmntinfo(statfs_t **mntbufp, int flags);
        int statfs(const char *path, statfs_t *buf);
    }

    @trusted bool parseStatfs(ref const(statfs_t) buf, out const(char)[] device, out const(char)[] mountDir, out const(char)[] type) nothrow {
        import std.string : fromStringz;
        type = fromStringz(buf.f_fstypename.ptr);
        device = fromStringz(buf.f_mntfromname.ptr);
        mountDir = fromStringz(buf.f_mntonname.ptr);
        return true;
    }
}

version(CRuntime_Glibc)
{
private:
    import core.stdc.stdio : FILE;
    struct mntent
    {
        char *mnt_fsname;   /* Device or server for filesystem.  */
        char *mnt_dir;      /* Directory mounted on.  */
        char *mnt_type;     /* Type of filesystem: ufs, nfs, etc.  */
        char *mnt_opts;     /* Comma-separated options for fs.  */
        int mnt_freq;       /* Dump frequency (in days).  */
        int mnt_passno;     /* Pass number for `fsck'.  */
    };

    extern(C) @nogc nothrow
    {
        FILE *setmntent(const char *file, const char *mode);
        mntent *getmntent(FILE *stream);
        mntent *getmntent_r(FILE * stream, mntent *result, char * buffer, int bufsize);
        int addmntent(FILE* stream, const mntent *mnt);
        int endmntent(FILE * stream);
        char *hasmntopt(const mntent *mnt, const char *opt);
    }

    @safe string decodeLabel(string label) nothrow pure
    {
        import std.string : replace;
        import std.conv : to;
        string res;
        res.reserve(label.length);
        for(size_t i = 0; i<label.length; ++i) {
            if (label[i] == '\\' && label.length > i+4 && label[i+1] == 'x') {
                try {
                    const code = to!ubyte(label[i+2..i+4], 16);
                    if (code >= 0x20 && code < 0x80) {
                        res ~= cast(char)code;
                        i+=3;
                        continue;
                    }
                } catch(Exception e) {

                }
            }
            res ~= label[i];
        }
        return res;
    }

    unittest
    {
        assert(decodeLabel("Label\\x20space") == "Label space");
        assert(decodeLabel("Label\\x5Cslash") == "Label\\slash");
        assert(decodeLabel("Label") == "Label");
        assert(decodeLabel("\\xNO") == "\\xNO");
    }

    @trusted string retrieveLabel(string fsName) nothrow {
        import std.file : dirEntries, SpanMode, readLink;
        import std.path : buildNormalizedPath, isAbsolute, baseName;
        import std.exception : collectException;
        enum byLabel = "/dev/disk/by-label";
        if (fsName.isAbsolute) { // /dev/sd*
            try {
                foreach(entry; dirEntries(byLabel, SpanMode.shallow))
                {
                    string resolvedLink;
                    if (entry.isSymlink && collectException(entry.readLink, resolvedLink) is null) {
                        auto normalized = buildNormalizedPath(byLabel, resolvedLink);
                        if (normalized == fsName)
                            return entry.name.baseName.decodeLabel();
                    }
                }
            } catch(Exception e) {

            }
        }
        return string.init;
    }

    unittest
    {
        assert(retrieveLabel("cgroup") == string.init);
    }

    @trusted bool parseMntent(ref const mntent ent, out const(char)[] device, out const(char)[] mountDir, out const(char)[] type) nothrow {
        import std.string : fromStringz;
        device = fromStringz(ent.mnt_fsname);
        mountDir = fromStringz(ent.mnt_dir);
        type = fromStringz(ent.mnt_type);
        return true;
    }
    @trusted bool parseMountsLine(const(char)[] line, out const(char)[] device, out const(char)[] mountDir, out const(char)[] type) nothrow {
        import std.algorithm.iteration : splitter;
        import std.string : representation;
        auto splitted = splitter(line.representation, ' ');
        if (!splitted.empty) {
            device = cast(const(char)[])splitted.front;
            splitted.popFront();
            if (!splitted.empty) {
                mountDir = cast(const(char)[])splitted.front;
                splitted.popFront();
                if (!splitted.empty) {
                    type = cast(const(char)[])splitted.front;
                    return true;
                }
            }
        }
        return false;
    }

    unittest
    {
        const(char)[] device, mountDir, type;
        parseMountsLine("/dev/sda2 /media/storage ext4 rw,noexec,relatime,errors=remount-ro,data=ordered 0 0", device, mountDir, type);
        assert(device == "/dev/sda2");
        assert(mountDir == "/media/storage");
        assert(type == "ext4");
    }
}

/**
 * Get mountpoint where the provided path resides on.
 */
@trusted string volumePath(string path)
out(result) {
    import std.path : isAbsolute;
    if (result.length) {
        assert(result.isAbsolute);
    }
}
body {
    if (path.length == 0)
        return string.init;
    import std.path : absolutePath;
    path = path.absolutePath;
    version(Posix) {
        import core.sys.posix.sys.types;
        import core.sys.posix.sys.stat;
        import core.sys.posix.unistd;
        import core.sys.posix.fcntl;
        import std.path : dirName;
        import std.string : toStringz;

        auto current = path;
        stat_t currentStat;
        if (stat(current.toStringz, &currentStat) != 0) {
            return null;
        }
        stat_t parentStat;
        while(current != "/") {
            string parent = current.dirName;
            if (lstat(parent.toStringz, &parentStat) != 0) {
                return null;
            }
            if (currentStat.st_dev != parentStat.st_dev) {
                return current;
            }
            current = parent;
        }
        return current;
    } else version(Windows) {
        const(wchar)* wpath = path.toUTF16z;
        wchar[MAX_PATH+1] buf;
        if (GetVolumePathName(wpath, buf.ptr, buf.length)) {
            return buf[0..wcslen(buf.ptr)].toUTF8;
        }
        return string.init;
    } else {
        return string.init;
    }
}

private struct VolumeInfoImpl
{
    enum Info : ushort {
        Type = 1 << 0,
        Device = 1 << 1,
        Label = 1 << 2,
        BytesAvailable = 1 << 3,
        BytesTotal = 1 << 4,
        BytesFree = 1 << 5,
        ReadOnly = 1 << 6,
        Ready = 1 << 7,
        Valid = 1 << 8,
    }

    @safe this(string path) nothrow {
        import std.path : isAbsolute;
        assert(path.isAbsolute);
        this.path = path;
    }
    version(Posix) @safe this(string mountPoint, string device, string type) nothrow {
        path = mountPoint;
        if (device.length)
            this.device = device;
        if (type.length)
            this.type = type;
    }
    version(FreeBSD) @safe this(string mountPoint, string device, string type, ref const(statfs_t) buf) nothrow {
        this(mountPoint, device, type);
        applyStatfs(buf);
        ready = valid = true;
    }

    BitFlags!Info retrieved;
    bool _readOnly;
    bool _ready;
    bool _valid;

    string path;
    string _device;
    string _type;
    string _label;

    long _bytesTotal = -1;
    long _bytesFree = -1;
    long _bytesAvailable = -1;

    @safe @property string device() nothrow {
        retrieve(Info.Device);
        return _device;
    }
    @safe @property void device(string dev) nothrow {
        retrieved |= Info.Device;
        _device = dev;
    }
    @safe @property string type() nothrow {
        retrieve(Info.Type);
        return _type;
    }
    @safe @property void type(string t) nothrow {
        retrieved |= Info.Type;
        _type = t;
    }
    @safe @property string label() nothrow {
        retrieve(Info.Label);
        return _label;
    }
    @safe @property void label(string name) nothrow {
        retrieved |= Info.Label;
        _label = name;
    }

    @safe @property long bytesTotal() nothrow {
        retrieve(Info.BytesTotal);
        return _bytesTotal;
    }
    @safe @property void bytesTotal(long bytes) nothrow {
        retrieved |= Info.BytesTotal;
        _bytesTotal = bytes;
    }
    @safe @property long bytesFree() nothrow {
        retrieve(Info.BytesFree);
        return _bytesFree;
    }
    @safe @property void bytesFree(long bytes) nothrow {
        retrieved |= Info.BytesFree;
        _bytesFree = bytes;
    }
    @safe @property long bytesAvailable() nothrow {
        retrieve(Info.BytesAvailable);
        return _bytesAvailable;
    }
    @safe @property void bytesAvailable(long bytes) nothrow {
        retrieved |= Info.BytesAvailable;
        _bytesAvailable = bytes;
    }
    @safe @property bool readOnly() nothrow {
        retrieve(Info.ReadOnly);
        return _readOnly;
    }
    @safe @property void readOnly(bool rdOnly) nothrow {
        retrieved |= Info.ReadOnly;
        _readOnly = rdOnly;
    }
    @safe @property bool valid() nothrow {
        import std.file : exists;
        retrieve(Info.Valid);
        return path.length && path.exists && _valid;
    }
    @safe @property bool valid(bool ok) nothrow {
        retrieved |= Info.Valid;
        _valid = ok;
        return ok;
    }
    @safe @property bool ready() nothrow {
        retrieve(Info.Ready);
        return path.length && _ready;
    }
    @safe @property void ready(bool r) nothrow {
        retrieved |= Info.Ready;
        _ready = r;
    }
    @safe void refresh() nothrow {
        retrieved = BitFlags!Info();
    }

    version(Posix)
    {
        import core.sys.posix.sys.statvfs;
        version(FreeBSD) {
            alias statfs_t STATFS_T;
            alias statfs STATFS;
            alias MNT_RDONLY READONLY_FLAG;
        } else {
            alias statvfs_t STATFS_T;
            alias statvfs STATFS;
            alias FFlag.ST_RDONLY READONLY_FLAG;
        }

        @trusted void retrieveVolumeInfo() nothrow {
            import std.string : toStringz;
            import std.exception : assumeWontThrow;

            STATFS_T buf;
            const result = assumeWontThrow(STATFS(toStringz(path), &buf)) == 0;
            ready = valid = result;
            if (result)
                applyStatfs(buf);
        }

        @safe void applyStatfs(ref const(STATFS_T) buf) nothrow {
            version(FreeBSD) {
                bytesTotal = buf.f_bsize * buf.f_blocks;
                bytesFree = buf.f_bsize * buf.f_bfree;
                bytesAvailable = buf.f_bsize * buf.f_bavail;
                readOnly = (buf.f_flags & READONLY_FLAG) != 0;
            } else {
                bytesTotal = buf.f_frsize * buf.f_blocks;
                bytesFree = buf.f_frsize * buf.f_bfree;
                bytesAvailable = buf.f_frsize * buf.f_bavail;
                readOnly = (buf.f_flag & READONLY_FLAG) != 0;
            }
        }
    }

    version(Posix) @trusted void retrieveDeviceAndType() nothrow {
        version(CRuntime_Glibc)
        {
            // we need to loop through all mountpoints again to find a type by path. Is there a faster way to get file system type?
            try {
                import std.stdio : File;
                foreach(line; File("/proc/self/mounts", "r").byLine) {
                    const(char)[] device, mountDir, type;
                    if (parseMountsLine(line, device, mountDir, type)) {
                        if (mountDir == path) {
                            this.device = device.idup;
                            this.type = type.idup;
                            break;
                        }
                    }
                }
            } catch(Exception e) {
                mntent ent;
                char[1024] buf;
                FILE* f = setmntent("/etc/mtab", "r");
                if (f is null)
                    return;
                scope(exit) endmntent(f);
                while(getmntent_r(f, &ent, buf.ptr, cast(int)buf.length) !is null) {
                    const(char)[] device, mountDir, type;
                    parseMntent(ent, device, mountDir, type);
                    if (mountDir == path) {
                        this.device = device.idup;
                        this.type = type.idup;
                        break;
                    }
                }
            }
        }
        else version(FreeBSD)
        {
            import std.string : toStringz;
            statfs_t buf;
            const result = statfs(toStringz(path), &buf) == 0;
            ready = valid = result;
            if (result) {
                const(char)[] device, mountDir, type;
                parseStatfs(buf, device, mountDir, type);
                this.device = device.idup;
                this.type = type.idup;
                applyStatfs(buf);
            }
        }
    }

    version(Windows) @trusted void retrieveVolumeInfo() nothrow {
        const oldmode = SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
        scope(exit) SetErrorMode(oldmode);

        import std.exception : collectException;
        const(wchar)* wpath;
        if (collectException(path.toUTF16z, wpath) !is null) {
            ready = valid = false;
            return;
        }
        wchar[MAX_PATH+1] name;
        wchar[MAX_PATH+1] fsType;
        DWORD flags = 0;
        const bool result = GetVolumeInformation(wpath,
                                                   name.ptr, name.length,
                                                   null, null,
                                                   &flags,
                                                   fsType.ptr, fsType.length) != 0;
        if (!result) {
            ready = false;
            valid = GetLastError() == ERROR_NOT_READY;
        } else {
            try {
                this.type = fsType[0..wcslen(fsType.ptr)].toUTF8;
                this.label = name[0..wcslen(name.ptr)].toUTF8;
            } catch(Exception e) {
            }

            ready = true;
            valid = true;
            readOnly = (flags & FILE_READ_ONLY_VOLUME) != 0;
        }
    }

    version(Windows) @trusted void retrieveSizes() nothrow
    {
        const oldmode = SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
        scope(exit) SetErrorMode(oldmode);

        import std.exception : collectException;
        const(wchar)* wpath;
        if (collectException(path.toUTF16z, wpath) !is null)
            return;
        ULARGE_INTEGER bytesA, bytesF, bytesT;
        ready = GetDiskFreeSpaceEx(wpath, &bytesA, &bytesT, &bytesF) != 0;
        bytesAvailable = cast(long)bytesA.QuadPart;
        bytesFree = cast(long)bytesF.QuadPart;
        bytesTotal = cast(long)bytesT.QuadPart;

    }

    @trusted void retrieve(Info requested) nothrow {
        if ((requested & retrieved) == BitFlags!Info(requested) || !path.length)
            return;
        with(Info)
        {
            version(Windows) {
                if (requested & (BitFlags!Info() | Ready | Valid | ReadOnly | Label | Type))
                    retrieveVolumeInfo();
                if (requested & (BitFlags!Info() | BytesAvailable | BytesFree | BytesTotal))
                    retrieveSizes();
            }
            version(Posix) {
                if (requested & (BitFlags!Info() | Ready | Valid | ReadOnly | BytesAvailable | BytesFree | BytesTotal))
                    retrieveVolumeInfo();
                if (requested & (BitFlags!Info() | Type | Device))
                    retrieveDeviceAndType();
            }
            version(CRuntime_Glibc) {
                if (requested & (BitFlags!Info() | Label))
                    label = retrieveLabel(device);
            }
        }
    }
}

/**
 * Represents a filesystem volume. Provides information about mountpoint, filesystem type and storage size.
 * All values except for $(D VolumeInfo.path) are retrieved on the first demand and then getting cached. Use $(D VolumeInfo.refresh) to refresh info.
 */
struct VolumeInfo
{
    /**
     * Construct an object that gives information about volume on which the provided path is located.
     * Params:
     *  path = either root path of volume or any file or directory that resides on the volume.
     */
    @trusted this(string path) {
        impl = RefCounted!VolumeInfoImpl(volumePath(path));
    }
    /// Root path of file system (mountpoint of partition).
    @trusted @property string path() nothrow {
        return impl.path;
    }
    /// Device string, e.g. /dev/sda. Currently implemented only on Linux and FreeBSD.
    @trusted @property string device() nothrow {
        return impl.device;
    }
    /**
     * File system type, e.g. ext4 on Linux or NTFS on Windows.
     */
    @trusted @property string type() nothrow {
        return impl.type;
    }
    /**
     * Name of volume. Empty string if volume label could not be retrieved.
     * In case the label is empty you may consider using the base name of volume path as a display name, possible in combination with type.
     */
    @trusted @property string label() nothrow {
        return impl.label;
    }
    /**
     * Total volume size.
     * Returns: total volume size in bytes or -1 if could not determine the size.
     */
    @trusted @property long bytesTotal() nothrow {
        return impl.bytesTotal;
    }
    /**
     * Free space in a volume
     * Note: This is size of free space in a volume, but actual free space available for the current user may be smaller.
     * Returns: number of free bytes in a volume or -1 if could not determine the number.
     * See_Also: $(D bytesAvailable)
     */
    @trusted @property long bytesFree() nothrow {
        return impl.bytesFree;
    }
    /**
     * Free space available for the current user.
     * This is what most tools and GUI applications show as free space.
     * Returns: number of free bytes available for the current user or -1 if could not determine the number.
     */
    @trusted @property long bytesAvailable() nothrow {
        return impl.bytesAvailable;
    }
    /// Whether the referenced filesystem is marked as readonly.
    @trusted @property bool readOnly() nothrow {
        return impl.readOnly;
    }
    @safe string toString() {
        import std.format;
        return format("VolumeInfo(%s, %s)", path, type);
    }
    /// Whether the filesystem is ready for work.
    @trusted @property bool ready() nothrow {
        return impl.ready;
    }
    /// Whether the object is valid (specified path exists).
    @trusted @property bool isValid() nothrow {
        return impl.valid;
    }
    /// Refresh cached info.
    @trusted void refresh() nothrow {
        return impl.refresh();
    }
private:
    this(VolumeInfoImpl impl) {
        this.impl = RefCounted!VolumeInfoImpl(impl);
    }
    RefCounted!VolumeInfoImpl impl;
}

unittest
{
    VolumeInfo info;
    assert(info.path == "");
    assert(info.type == "");
    assert(info.device == "");
    assert(info.label == "");
    assert(info.bytesTotal < 0);
    assert(info.bytesAvailable < 0);
    assert(info.bytesFree < 0);
    assert(!info.readOnly);
    assert(!info.ready);
    assert(!info.isValid);
}

/**
 * The list of currently mounted volumes.
 */
VolumeInfo[] mountedVolumes() {
    VolumeInfo[] res;
    version(CRuntime_Glibc) {
        try {
            import std.stdio : File;

            foreach(line; File("/proc/self/mounts", "r").byLine) {
                const(char)[] device, mountDir, type;
                if (parseMountsLine(line, device, mountDir, type)) {
                    if (!isSpecialFileSystem(mountDir, type)) {
                        res ~= VolumeInfo(VolumeInfoImpl(mountDir.idup, device.idup, type.idup));
                    }
                }
            }
        } catch(Exception e) {
            res.length = 0;
            res ~= VolumeInfo(VolumeInfoImpl("/"));

            mntent ent;
            char[1024] buf;
            FILE* f = setmntent("/etc/mtab", "r");
            if (f is null)
                return res;

            scope(exit) endmntent(f);
            while(getmntent_r(f, &ent, buf.ptr, cast(int)buf.length) !is null) {
                const(char)[] device, mountDir, type;
                parseMntent(ent, device, mountDir, type);

                if (mountDir == "/" || isSpecialFileSystem(mountDir, type))
                    continue;

                res ~= VolumeInfo(VolumeInfoImpl(mountDir.idup, device.idup, type.idup));
            }
        }
    }
    else version(FreeBSD) {
        import std.string : fromStringz;
        res ~= VolumeInfo(VolumeInfoImpl("/"));

        statfs_t* mntbufsPtr;
        int mntbufsLen = getmntinfo(&mntbufsPtr, 0);
        if (mntbufsLen) {
            auto mntbufs = mntbufsPtr[0..mntbufsLen];

            foreach(buf; mntbufs) {
                const(char)[] device, mountDir, type;
                parseStatfs(buf, device, mountDir, type);

                if (mountDir == "/" || isSpecialFileSystem(mountDir, type))
                    continue;

                res ~= VolumeInfo(VolumeInfoImpl(mountDir.idup, device.idup, type.idup, buf));
            }
        }
    }
    else version(Posix) {
        res ~= VolumeInfo(VolumeInfoImpl("/"));
    }

    version (Windows) {
        const oldmode = SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
        scope(exit) SetErrorMode(oldmode);
        const uint mask = GetLogicalDrives();
        foreach(int i; 0 .. 26) {
            if (mask & (1 << i)) {
                const char letter = cast(char)('A' + i);
                string path = letter ~ ":\\";
                res ~= VolumeInfo(VolumeInfoImpl(path));
            }
        }
    }
    return res;
}
